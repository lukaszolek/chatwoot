# Composes a personalized intro email for a participant, using a
# CampaignTemplate as the anchor tone/structure plus the participant's
# profile for personalization (first name, city, website, instagram).
#
# Used by operator-side "regenerate intro" flows and by smoke-test
# runbooks. The engine's SendTemplate executor renders templates
# directly without LLM personalization today — this service stands
# ready for when we swap it in for intro-only stages.
#
# Returns the same shape as ReplyClassifier so DecisionLogger can log
# uniformly across all decision types.
class Outreach::Llm::IntroComposer
  PROMPT_VERSION = 'outreach.compose_intro.v1'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a concise copywriter for Framky's photographer partnership
    programme. Compose a short, warm, non-pushy intro email that invites
    the photographer to join. Preserve the language of the template.
    Return STRICT JSON with keys:
      - subject (string)
      - body (string; plain text, no HTML)
      - reasoning (one-sentence note on the personalization choice)

    Respect the template's tone and structure; only personalize names,
    city, website references, and mention of Instagram handle when
    available. Keep CTA clear: the recipient can reply "yes" or click
    the link. Do NOT include unsubscribe text — the sending system
    appends it.

    Return raw JSON only.
  PROMPT

  def initialize(participant:, template:, locale: nil)
    @participant = participant
    @template = template
    @locale = locale
  end

  # rubocop:disable Metrics/MethodLength
  def call
    ctx = LlmFormatter::PhotographerPartnerLlmFormatter.new(@participant).format
    user_prompt = build_user_prompt(ctx)

    result = client.ask_json!(
      model: client.compose_model,
      system: SYSTEM_PROMPT,
      user: user_prompt,
      temperature: 0.3
    )

    parsed = result.fetch(:parsed)

    {
      subject: parsed['subject'].to_s,
      body: parsed['body'].to_s,
      reasoning: parsed['reasoning'].to_s,
      model: client.compose_model,
      prompt_version: PROMPT_VERSION,
      input_digest: Digest::SHA256.hexdigest(user_prompt),
      output: parsed,
      token_usage: result[:token_usage],
      latency_ms: result[:latency_ms]
    }
  end
  # rubocop:enable Metrics/MethodLength

  private

  def client
    @client ||= Outreach::Llm::Client.new
  end

  def build_user_prompt(ctx)
    locale = @locale || ctx[:locale]
    <<~USER
      Locale: #{locale}
      Template subject: #{@template.subject}
      Template body:
      #{@template.body}
      Photographer profile: #{ctx[:profile]}
    USER
  end
end
