# Composes a reply to a photographer's inbound message. Has access to
# the agent toolbox for record reads/writes (consent, partnership status,
# notes) and Framky-backend lookups (registration, commission, invoice).
#
# Differences from the text-only composers:
#   - Caller passes a Toolbox; we expose its tools to the LLM via
#     ask_with_tools!.
#   - LLM may iterate (call tools, then write final text). Output JSON
#     is best-effort — if the model returns plain text after a tool
#     chain, we treat the text as body and synthesize a subject from
#     the prior thread.
#   - If the LLM (or any tool) calls escalate_to_operator → composer
#     returns { escalate: true, reason: } and the executor refuses to
#     send / draft anything.
class Outreach::Llm::MessageComposer::Reply < Outreach::Llm::MessageComposer::Base
  SLOT = 'reply'.freeze
  PROMPT_VERSION = 'outreach.compose_reply.v1'.freeze

  def initialize(participant:, toolbox:, locale: nil, conversation: nil, operator_hint: nil)
    super(participant: participant, locale: locale, conversation: conversation, operator_hint: operator_hint)
    @toolbox = toolbox
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    user_prompt = build_user_prompt
    system_prompt = build_system_prompt

    result = client.ask_with_tools!(
      model: client.compose_model,
      system: system_prompt,
      user: user_prompt,
      tools: @toolbox.tools,
      temperature: 0.3
    )

    return build_escalation(result, started) if escalation_requested?(result)

    build_reply_success(result, user_prompt, started)
  rescue Outreach::Llm::Client::LlmError => e
    Rails.logger.warn("[outreach.composer.reply] llm_error=#{e.class}: #{e.message.truncate(200)}")
    { escalate: true, reason: "llm_error:#{e.class}: #{e.message.truncate(120)}" }
  end

  private

  def temperature
    0.3
  end

  def slot_instruction
    <<~TEXT.strip
      SLOT INSTRUCTION — REPLY:
        You are answering an inbound email from the photographer
        (visible at the bottom of the conversation history).

        - You may call tools to look up facts before answering. ALWAYS
          pass sender_email = the email address of the inbound's From
          line (visible in the photographer profile block above).
        - DO NOT call any tool with an email different from that sender.
          The tools will refuse and you'll waste a turn.
        - When the photographer asks about commission balance,
          registration status, or wants to submit an invoice — call the
          relevant tool and quote the returned numbers verbatim.
        - When the photographer says they want OUT (declined, refuse,
          unsubscribe) → call update_marketing_consent(state="declined")
          AND set_partnership_status(status="do_not_contact") then write
          a short polite acknowledgement.
        - When the photographer's reply is sensitive (legal, refund,
          dispute) or you don't have data to answer → call
          escalate_to_operator with a one-sentence reason and STOP.
        - For routine clarifications you can answer directly using
          KNOWLEDGE (program_rules, FAQ, product) — keep it short.
        - Length: ≤ 8 sentences.
    TEXT
  end

  def build_user_prompt
    [
      "Locale: #{resolved_locale}",
      "Photographer profile: #{formatter[:profile]}",
      "Sender email (use this exact value in any tool call's sender_email param): #{participant.participatable.email}",
      website_snippet_block,
      conversation_history_block,
      operator_hint_block,
      "INBOUND MESSAGE TO ANSWER:\n#{formatter[:reply_text]}"
    ].compact.join("\n\n")
  end

  def escalation_requested?(result)
    return false if result[:tool_calls].blank?

    result[:tool_calls].any? { |tc| tc[:name].to_s == 'escalate_to_operator' }
  end

  def build_escalation(result, started)
    escalation = result[:tool_calls].find { |tc| tc[:name].to_s == 'escalate_to_operator' }
    {
      escalate: true,
      reason: escalation&.dig(:params, 'reason') || escalation&.dig(:params, :reason) || 'unspecified',
      tool_calls: result[:tool_calls],
      latency_ms: result[:latency_ms] || latency_ms_since(started)
    }
  end

  def build_reply_success(result, user_prompt, started)
    parsed = result[:parsed] || {}
    body = parsed['body'].presence || result[:raw_content].to_s.strip
    # Force Re-prefixed thread subject; ignore whatever subject the LLM
    # invented. Email clients (Gmail, Outlook) thread by normalized
    # subject — diverging means the recipient sees a brand-new
    # conversation, even with matching In-Reply-To headers.
    subject = infer_subject_from_thread

    {
      subject: subject,
      body: body,
      locale: resolved_locale,
      model: client.compose_model,
      prompt_version: self.class::PROMPT_VERSION,
      input_digest: Digest::SHA256.hexdigest(user_prompt),
      output: parsed,
      tool_calls: result[:tool_calls],
      token_usage: result[:token_usage] || {},
      latency_ms: result[:latency_ms] || latency_ms_since(started),
      fallback: false
    }
  end

  def infer_subject_from_thread
    last_outgoing = conversation&.messages&.where(message_type: :outgoing, private: false)
                                &.order(created_at: :desc)&.first
    prev_subject = last_outgoing&.outreach_draft_subject || last_outgoing&.content_attributes&.dig('email', 'subject')
    return "Re: Framky" if prev_subject.blank?

    prev_subject.start_with?('Re:') ? prev_subject : "Re: #{prev_subject}"
  end
end
