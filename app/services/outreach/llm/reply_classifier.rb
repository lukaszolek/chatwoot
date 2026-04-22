# Classifies a photographer's inbound reply into one of 8 intent classes
# (§4.3 of the partnerships plan) and returns a confidence score.
#
# Contract (consumed by Outreach::Engine::Executors::ClassifyReply):
#   {
#     intent_class: String,   # one of INTENT_CLASSES
#     confidence: Float,      # 0.0-1.0
#     reasoning: String,
#     model: String,
#     prompt_version: String,
#     input_digest: String,
#     output: Hash,
#     token_usage: Hash,
#     latency_ms: Integer
#   }
#
# Falls back to `{ intent_class: 'unclear', confidence: 0.0 }` when the
# LLM returns malformed JSON or an unknown intent class — the executor
# then routes to escalation, which is the safe default.
class Outreach::Llm::ReplyClassifier
  INTENT_CLASSES = %w[
    interested_signup interested_commission asks_showroom asks_product
    declined out_of_office spam unclear
  ].freeze

  PROMPT_VERSION = 'outreach.classify.v1'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You classify inbound replies to an outbound photographer-partnership
    outreach campaign. Return STRICT JSON with keys:
      - intent_class (one of: #{INTENT_CLASSES.join(', ')})
      - confidence (float 0..1, 1 = certain)
      - reasoning (one-sentence explanation)

    Intent class definitions:
      - interested_signup: wants to join / asking how to sign up
      - interested_commission: curious, asking about commission/payment
      - asks_showroom: asking about showroom / physical collaboration
      - asks_product: asking about the product (what is Framky, materials, delivery)
      - declined: not interested / polite no
      - out_of_office: auto-reply, vacation responder
      - spam: irrelevant, sales pitch, clearly not engaging
      - unclear: anything not confidently above

    Return raw JSON only — no markdown, no prose.
  PROMPT

  def initialize(participant:, conversation: nil, locale: nil)
    @participant = participant
    @conversation = conversation || participant.conversation
    @locale = locale
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def call
    prompt_context = LlmFormatter::PhotographerPartnerLlmFormatter.new(@participant).format
    user_prompt = build_user_prompt(prompt_context)

    result = client.ask_json!(
      model: client.classify_model,
      system: SYSTEM_PROMPT,
      user: user_prompt,
      temperature: 0.0
    )

    parsed = result.fetch(:parsed)
    intent_class = sanitise_intent(parsed['intent_class'])
    confidence = parsed['confidence'].to_f.clamp(0.0, 1.0)

    {
      intent_class: intent_class,
      confidence: intent_class == 'unclear' ? [confidence, 0.0].max : confidence,
      reasoning: parsed['reasoning'].to_s,
      model: client.classify_model,
      prompt_version: PROMPT_VERSION,
      input_digest: Digest::SHA256.hexdigest(user_prompt),
      output: parsed,
      token_usage: result[:token_usage],
      latency_ms: result[:latency_ms]
    }
  rescue Outreach::Llm::Client::LlmError => e
    Rails.logger.error("[outreach.llm.classify] participant=#{@participant.id} error=#{e.class}: #{e.message}")
    {
      intent_class: 'unclear', confidence: 0.0,
      reasoning: "llm_error:#{e.class}", model: client.classify_model,
      prompt_version: PROMPT_VERSION, input_digest: nil,
      output: { 'error' => e.message }, token_usage: {}, latency_ms: nil
    }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  def client
    @client ||= Outreach::Llm::Client.new
  end

  def sanitise_intent(raw)
    return 'unclear' if raw.blank?

    value = raw.to_s.strip.downcase.tr(' -', '_')
    INTENT_CLASSES.include?(value) ? value : 'unclear'
  end

  def build_user_prompt(ctx)
    locale = @locale || ctx[:locale]
    <<~USER
      Locale hint: #{locale}
      Photographer profile: #{ctx[:profile]}
      Last outreach message we sent:
      #{ctx[:last_intro_summary] || '(none)'}
      Reply to classify:
      #{ctx[:reply_text] || '(empty)'}
      Recent thread (oldest first):
      #{ctx[:conversation_history].join("\n")}
    USER
  end
end
