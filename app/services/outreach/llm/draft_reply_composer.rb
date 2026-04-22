# Composes a draft reply given (a) the classified intent class from
# ReplyClassifier and (b) a CampaignTemplate matching the intent slot
# (e.g. `reply_interested_commission`, `reply_asks_product`).
#
# Used by C6.1 draft-approve flow: when confidence sits in the mid band
# (0.5 ≤ c < min_confidence) the engine creates a CampaignDraft with
# subject/body from this composer for the operator to review.
class Outreach::Llm::DraftReplyComposer
  PROMPT_VERSION = 'outreach.draft_reply.v1'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a concise, warm assistant composing a reply to a photographer
    who responded to a partnership outreach. Ground the reply in the
    provided template (which represents Framky's desired voice for this
    intent class) and the thread context. Preserve the template's
    language (locale). Return STRICT JSON:
      - subject (string; keep Re: prefix if the thread already has one)
      - body (plain text, no HTML)
      - reasoning (one sentence)

    Do not include unsubscribe text — it is appended by the sender.
    Return raw JSON only.
  PROMPT

  def initialize(participant:, intent_class:, template:, locale: nil)
    @participant = participant
    @intent_class = intent_class
    @template = template
    @locale = locale
  end

  # rubocop:disable Metrics/MethodLength
  def call
    ctx = LlmFormatter::PhotographerPartnerLlmFormatter.new(@participant).format
    user_prompt = build_user_prompt(ctx)

    result = client.ask_json!(
      model: client.draft_model,
      system: SYSTEM_PROMPT,
      user: user_prompt,
      temperature: 0.3
    )

    parsed = result.fetch(:parsed)

    {
      subject: parsed['subject'].to_s,
      body: parsed['body'].to_s,
      reasoning: parsed['reasoning'].to_s,
      model: client.draft_model,
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
      Detected intent: #{@intent_class}
      Reply template (use as voice/structure anchor):
      Subject: #{@template.subject}
      Body:
      #{@template.body}

      Photographer profile: #{ctx[:profile]}
      Their incoming reply:
      #{ctx[:reply_text]}
      Thread so far (oldest first):
      #{ctx[:conversation_history].join("\n")}
    USER
  end
end
