# Regenerates an outreach draft Message in place, with an optional
# operator prompt that gets passed to the LLM as a strict instruction.
#
# Behaviors:
#   1. Re-runs the appropriate composer (intro / reminder / breakup / reply)
#      with operator_hint = the operator's instruction text.
#   2. Updates the draft Message's content + content_attributes.email.subject.
#   3. Appends an entry to additional_attributes.regeneration_history with
#      previous + new subject/body, the operator_prompt, and metadata.
#   4. Increments iteration_count.
#   5. Records an OutboundCampaignLearning row (source_kind: operator_prompt)
#      so the next composer call sees what the operator wanted.
class Outreach::Drafts::RegenerateService
  class Error < StandardError; end

  def initialize(draft_message:, user:, operator_prompt:)
    @draft_message = draft_message
    @user = user
    @operator_prompt = operator_prompt.to_s.strip
  end

  def call
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'
    raise Error, 'operator_prompt is required' if operator_prompt.empty?

    participant = resolve_participant
    raise Error, 'participant not found' unless participant

    composed = compose(participant)
    return { error: 'composer_escalated', reason: composed[:reason] } if composed[:escalate]

    apply_regeneration!(composed)
    record_learning!(participant, composed)

    { ok: true, subject: composed[:subject], body: composed[:body],
      iteration_count: draft_message.reload.additional_attributes['iteration_count'] }
  end

  private

  attr_reader :draft_message, :user, :operator_prompt

  def slot
    @slot ||= draft_message.additional_attributes['template_slot'].to_s
  end

  def locale
    draft_message.additional_attributes['locale']
  end

  def resolve_participant
    pid = draft_message.additional_attributes['campaign_participant_id']
    pid ? CampaignParticipant.find_by(id: pid) : nil
  end

  def compose(participant)
    with_llm_errors_wrapped(participant) do
      compose_for_slot(participant)
    end
  end

  def compose_for_slot(participant)
    case slot
    when 'intro'
      Outreach::Llm::MessageComposer::Intro.new(participant: participant, locale: locale,
                                                operator_hint: operator_prompt).call
    when 'reminder'
      Outreach::Llm::MessageComposer::Reminder.new(participant: participant, locale: locale,
                                                   operator_hint: operator_prompt).call
    when 'breakup'
      Outreach::Llm::MessageComposer::Breakup.new(participant: participant, locale: locale,
                                                  operator_hint: operator_prompt).call
    when 'reply'
      compose_reply(participant)
    else
      raise Error, "unknown slot '#{slot}'"
    end
  end

  def with_llm_errors_wrapped(participant)
    yield
  rescue Outreach::Llm::Client::LlmError, RubyLLM::Error, Faraday::Error, Net::ReadTimeout, JSON::ParserError => e
    Rails.logger.warn(
      "[outreach.drafts.regenerate] draft=#{draft_message.id} participant=#{participant&.id} error=#{e.class}: #{e.message}"
    )
    raise Error, "LLM regeneration failed (#{e.class}: #{e.message}). Draft was not changed."
  end

  def compose_reply(participant)
    sender_email = participant.participatable.email
    toolbox = Outreach::Agent::Toolbox.new(
      scoped_sender_email: sender_email,
      account: participant.account,
      conversation: draft_message.conversation,
      draft_message: draft_message
    )
    Outreach::Llm::MessageComposer::Reply.new(
      participant: participant,
      conversation: draft_message.conversation,
      toolbox: toolbox,
      operator_hint: operator_prompt
    ).call
  end

  def apply_regeneration!(composed)
    additional = draft_message.additional_attributes.deep_dup
    history = Array(additional['regeneration_history'])
    history << regeneration_history_entry(composed)
    additional['regeneration_history'] = history
    additional.merge!(regeneration_attributes(composed, additional))

    draft_message.update!(
      content: legal_body(composed),
      content_attributes: draft_message.content_attributes.deep_merge('email' => { 'subject' => composed[:subject] }),
      additional_attributes: additional
    )
    Outreach::TranslateForAgents.call(message: draft_message, source_locale: composed[:locale] || locale)
  end

  def regeneration_history_entry(composed)
    {
      'at' => Time.current.iso8601,
      'operator_user_id' => user&.id,
      'operator_prompt' => operator_prompt,
      'prev_subject' => draft_message.outreach_draft_subject,
      'prev_body' => draft_message.content,
      'new_subject' => composed[:subject],
      'new_body' => legal_body(composed),
      'model' => composed[:model],
      'latency_ms' => composed[:latency_ms]
    }
  end

  def regeneration_attributes(composed, additional)
    {
      'iteration_count' => additional['iteration_count'].to_i + 1,
      'composer_model' => composed[:model],
      'composer_prompt_version' => composed[:prompt_version],
      'composer_input_digest' => composed[:input_digest]
    }
  end

  def legal_body(composed)
    Outreach::LegalFooter.ensure_stop_opt_out(composed[:body], locale: composed[:locale] || locale)
  end

  def record_learning!(participant, _composed)
    OutboundCampaignLearning.create!(
      outbound_campaign: participant.outbound_campaign,
      user: user,
      draft_message: draft_message,
      source_kind: 'operator_prompt',
      slot: slot,
      locale: locale,
      content: operator_prompt
    )
  end
end
