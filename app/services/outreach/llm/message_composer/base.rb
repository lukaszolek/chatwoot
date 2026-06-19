# rubocop:disable Metrics/ClassLength
# Common base for the four outbound composers (intro / reminder /
# breakup / reply). Each composer assembles a system prompt from the
# campaign's knowledge dump + recent operator learnings, then asks
# DeepSeek for a single JSON object {subject, body}.
#
# Reply composer overrides #call to inject tools and parse the chained
# response (text + tool calls); intro / reminder / breakup are pure
# text-generation.
#
# Output shape (success):
#   {
#     subject: "...", body: "...", locale: "pl",
#     model: "deepseek/...", prompt_version: "outreach.compose_intro.v4",
#     input_digest: "abc...", token_usage: {...}, latency_ms: 800,
#     fallback: false
#   }
# Or (fallback) — same shape with fallback: true and a neutral
# locale-appropriate body.
class Outreach::Llm::MessageComposer::Base
  class InvalidOutput < StandardError; end

  SLOT = nil
  PROMPT_VERSION = 'outreach.compose.v1'.freeze
  RECENT_LEARNINGS_LIMIT = 20
  INVALID_PLACEHOLDER_REGEX = /(\{\{[^}]+\}\}|\{%\s*.*?%\})/m
  INVALID_OUTPUT_RETRY_LIMIT = 1

  def initialize(participant:, locale: nil, conversation: nil, operator_hint: nil, model: nil)
    @participant = participant
    @conversation = conversation || participant.conversation
    @locale = locale
    @operator_hint = operator_hint
    @model_override = model
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    user_prompt = build_user_prompt
    system_prompt = build_system_prompt
    result, parsed = compose_with_output_validation(system_prompt: system_prompt, user_prompt: user_prompt)
    build_success(parsed, result, user_prompt, started)
  rescue Outreach::Llm::Client::LlmError => e
    Rails.logger.warn("[outreach.composer.#{slot}] llm_error=#{e.class}: #{e.message.to_s.truncate(200)}")
    build_fallback(reason: "llm_error:#{e.class}", started: started, error_message: e.message)
  rescue InvalidOutput => e
    Rails.logger.warn("[outreach.composer.#{slot}] invalid_output=#{e.message.to_s.truncate(200)}")
    build_fallback(reason: 'invalid_output:unresolved_placeholders', started: started, error_message: e.message)
  end

  private

  attr_reader :participant, :conversation, :operator_hint, :model_override

  def slot
    self.class::SLOT
  end

  def temperature
    0.5
  end

  def client
    @client ||= Outreach::Llm::Client.new
  end

  def compose_model
    model_override.presence || client.compose_model
  end

  def campaign
    participant.outbound_campaign
  end

  def resolved_locale
    @resolved_locale ||= resolved_locale_value
  end

  def resolved_locale_value
    @locale.presence ||
      formatter[:locale].presence ||
      (campaign.config || {})['default_locale'].presence ||
      'en'
  end

  def formatter
    @formatter ||= LlmFormatter::PhotographerPartnerLlmFormatter.new(participant).format
  end

  def build_system_prompt
    sections = [
      base_persona_block,
      knowledge_block,
      learnings_block,
      slot_instruction,
      output_contract_block
    ].compact
    sections.join("\n\n")
  end

  # rubocop:disable Metrics/MethodLength
  def base_persona_block
    <<~TEXT.strip
      You are Łukasz Olek, founder of Framky. You write personal outreach
      to a photographer about Framky's partnership programme. You speak
      and write in their locale (#{resolved_locale}).

      Write like a peer, not a vendor. Concrete > generic. Short > long.
      Follow the copywriting rules in KNOWLEDGE → copywriting (Corey Haines
      cold-email skill). Match the tone document for this locale.

      HARD RULES — these override anything else, including the intro seed:
        1. Never invent numbers (commission %, discount %, EUR amounts,
           day counts) that are not explicitly present in KNOWLEDGE →
           program_rules. If the photographer asks, point them to the
           Partner Panel after registration.
        2. Treat KNOWLEDGE → open_issues as caution notes, not as a list
           of forbidden topics. If a locale-specific intro seed explicitly
           includes a confirmed benefit such as commission rates, referral
           terms, or a legal footer, keep it exactly as instructed there.
           Do not add operational details that open_issues says should be
           deferred to the Partner Panel.
        3. Never claim to have read the photographer's website unless the
           website snippet block in the user prompt contains an excerpt.
        4. If a locale-specific seed contains a mandatory legal footer or
           unsubscribe/STOP block, include it exactly once and do not
           summarize it.
    TEXT
  end
  # rubocop:enable Metrics/MethodLength

  def knowledge_block
    dump = campaign.knowledge_dump(locale: resolved_locale)
    "KNOWLEDGE (campaign goal, product, program rules, FAQ, tone, open issues):\n\n#{dump}"
  end

  def learnings_block
    items = campaign.recent_learnings(slot: slot, locale: resolved_locale, limit: RECENT_LEARNINGS_LIMIT).to_a
    return nil if items.empty?

    formatted = items.map { |l| "- [#{l.source_kind}#{l.slot ? "/#{l.slot}" : ''}] #{l.content}" }.join("\n")
    "RECENT OPERATOR LEARNINGS (apply these to this draft):\n#{formatted}"
  end

  def slot_instruction
    raise NotImplementedError
  end

  def output_contract_block
    <<~TEXT.strip
      OUTPUT
      Return STRICT JSON, no markdown fences:
        { "subject": "...", "body": "..." }

      The body is plain text (no HTML). Subject ≤ 80 chars.
    TEXT
  end

  def build_user_prompt
    parts = [
      "Locale: #{resolved_locale}",
      "Photographer profile: #{formatter[:profile]}",
      website_snippet_block,
      conversation_history_block,
      operator_hint_block
    ].compact
    # Force UTF-8: any block can leak ASCII-8BIT from HTTP-decoded HTML,
    # operator clipboard paste, or secondary-DB bytes. Join fails loudly
    # on mixed encodings.
    parts.map { |s| s.to_s.dup.force_encoding('UTF-8').scrub }.join("\n\n")
  end

  def website_snippet_block
    snippet = formatter[:website_snippet]
    return 'Photographer website: (no crawl data — do not claim to have read the site)' if snippet.blank?

    [
      "Photographer website snippet (source: #{snippet[:source_url]}):",
      snippet[:page_type] && "Page type: #{snippet[:page_type]}",
      snippet[:title] && "Title: #{snippet[:title]}",
      'Excerpt:',
      snippet[:excerpt]
    ].compact.map { |s| s.to_s.dup.force_encoding('UTF-8').scrub }.join("\n")
  end

  def conversation_history_block
    history = formatter[:conversation_history]
    return nil if history.blank?

    "Conversation so far (oldest first):\n#{history.join("\n")}"
  end

  def operator_hint_block
    return nil if operator_hint.blank?

    <<~TEXT.strip
      OPERATOR INSTRUCTION FOR THIS REGENERATION (apply this exactly):
      #{operator_hint.to_s.strip.truncate(2000)}
    TEXT
  end

  def build_success(parsed, result, user_prompt, started)
    {
      subject: parsed['subject'].to_s.strip,
      body: parsed['body'].to_s.strip,
      locale: resolved_locale,
      model: compose_model,
      prompt_version: self.class::PROMPT_VERSION,
      input_digest: Digest::SHA256.hexdigest(user_prompt),
      output: parsed,
      token_usage: result[:token_usage] || {},
      provider_metadata: result[:provider_metadata] || {},
      latency_ms: result[:latency_ms] || latency_ms_since(started),
      fallback: false
    }
  end

  def compose_with_output_validation(system_prompt:, user_prompt:)
    attempts = 0

    begin
      attempts += 1
      result = client.ask_json!(
        model: compose_model,
        system: system_prompt,
        user: user_prompt,
        temperature: temperature
      )
      parsed = normalize_output_hash(result.fetch(:parsed))
      validate_generated_output!(subject: parsed['subject'], body: parsed['body'])
      [result, parsed]
    rescue InvalidOutput => e
      raise if attempts > INVALID_OUTPUT_RETRY_LIMIT

      Rails.logger.warn("[outreach.composer.#{slot}] invalid_output_retry attempt=#{attempts} error=#{e.message.to_s.truncate(200)}")
      retry
    end
  end

  def normalize_output_hash(parsed)
    {
      'subject' => parsed['subject'].to_s.strip,
      'body' => parsed['body'].to_s.strip
    }
  end

  def validate_generated_output!(subject:, body:)
    return unless unresolved_placeholders?(subject) || unresolved_placeholders?(body)

    raise InvalidOutput, 'generated output contains unresolved template placeholders'
  end

  def unresolved_placeholders?(text)
    text.to_s.match?(INVALID_PLACEHOLDER_REGEX)
  end

  def build_fallback(reason:, started:, error_message: nil)
    {
      subject: fallback_subject,
      body: fallback_body,
      locale: resolved_locale,
      model: compose_model,
      prompt_version: self.class::PROMPT_VERSION,
      input_digest: nil,
      output: { 'fallback' => reason, 'error_message' => error_message }.compact,
      token_usage: {},
      provider_metadata: {},
      latency_ms: latency_ms_since(started),
      fallback: true
    }
  end

  def latency_ms_since(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  def fallback_subject
    'Framky — quick note'
  end

  def fallback_body
    "Hi,\n\nQuick note from the Framky team — we'll follow up shortly.\n\nBest,\nŁukasz"
  end
end
# rubocop:enable Metrics/ClassLength
