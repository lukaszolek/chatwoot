# SendTemplate executor (LLM-first edition).
#
# Despite the historical name, this executor no longer renders a Liquid
# template. The stage's `template_slot` (intro / reminder / breakup) is
# the routing key for an Outreach::Llm::MessageComposer subclass that
# generates the entire mail from the campaign knowledge base + recent
# operator learnings + conversation history. (The slot name is preserved
# for blueprint compatibility — renaming would be a YAML breaker.)
#
# Pacing guards (the same as before):
#   - already_replied → pause terminal
#   - outbound_count >= MAX_OUTBOUND → pause terminal
#   - last_outbound_at within MIN_GAP → park, retry later
#
# Output path:
#   - campaign.manual_review_mode? → create a Message with
#     private: true + additional_attributes['outreach_draft'] = true
#     INSIDE the conversation thread. Stage does NOT advance; advancement
#     happens when the operator approves the draft (Messages::ApproveOutreachDraft).
#   - autopilot → enqueue Outreach::SendEmailJob, advance stage,
#     stamp last_outbound_at.
class Outreach::Engine::Executors::SendTemplate < Outreach::Engine::Executors::Base
  MAX_OUTBOUND = 3
  MIN_GAP = 7.days

  COMPOSERS = {
    'intro' => Outreach::Llm::MessageComposer::Intro,
    'reminder' => Outreach::Llm::MessageComposer::Reminder,
    'breakup' => Outreach::Llm::MessageComposer::Breakup
  }.freeze

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def call
    return skip_replied! if already_replied?
    return skip_cap! if outbound_count >= MAX_OUTBOUND
    return park_until_gap_elapsed! if gap_not_elapsed?

    composer_class = COMPOSERS[stage.template_slot]
    unless composer_class
      pause_terminal!(reason: "no_composer_for_slot:#{stage.template_slot}")
      return
    end

    composed = composer_class.new(participant: participant).call
    log_decision!(composed)

    conversation = Outreach::Engine::ConversationResolver.new(participant).conversation

    if campaign.manual_review_mode?
      create_outreach_draft_message!(conversation, composed)
      park_for_operator!
      # Stage stays put. Operator will trigger approve/reject which
      # advances or escalates the participant. We don't set
      # last_outbound_at — nothing has actually been sent yet.
    else
      Outreach::SendEmailJob.perform_later(
        participant_id: participant.id,
        conversation_id: conversation.id,
        subject: composed[:subject],
        body: composed[:body],
        template_slot: stage.template_slot,
        locale: composed[:locale]
      )
      advance_after_send
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  def create_outreach_draft_message!(conversation, composed)
    message = conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      private: true,
      sender: campaign.sender_user,
      content: composed[:body],
      content_type: 'text',
      content_attributes: { email: { subject: composed[:subject] } },
      additional_attributes: {
        'outreach_draft' => true,
        'draft_status' => 'pending',
        'template_slot' => stage.template_slot,
        'locale' => composed[:locale],
        'composer_model' => composed[:model],
        'composer_prompt_version' => composed[:prompt_version],
        'composer_input_digest' => composed[:input_digest],
        'iteration_count' => 1,
        'regeneration_history' => [],
        'campaign_participant_id' => participant.id,
        'outbound_campaign_id' => campaign.id,
        'fallback' => composed[:fallback]
      }
    )
    Outreach::TranslateForAgents.call(message: message, source_locale: composed[:locale])
    message
  end

  def log_decision!(composed)
    decision_type = "compose_#{stage.template_slot}".to_sym
    Outreach::Llm::DecisionLogger.record!(
      participant: participant,
      decision_type: decision_type,
      input: composed[:input_digest] || "fallback:#{stage.template_slot}",
      output: composed[:output] || {},
      model: composed[:model],
      prompt_version: composed[:prompt_version],
      token_usage: composed[:token_usage],
      latency_ms: composed[:latency_ms]
    )
  rescue StandardError => e
    Rails.logger.warn("[outreach.send_template] decision_log_failed=#{e.class}: #{e.message.truncate(200)}")
  end

  def already_replied?
    participant.last_inbound_at.present? &&
      participant.last_outbound_at.present? &&
      participant.last_inbound_at > participant.last_outbound_at
  end

  def outbound_count
    return 0 unless participant.conversation_id

    participant.conversation.messages
               .where(message_type: :outgoing, private: false)
               .count
  end

  def gap_not_elapsed?
    return false if participant.last_outbound_at.blank?

    participant.last_outbound_at > MIN_GAP.ago
  end

  def skip_replied!
    pause_terminal!(reason: 'replied_before_send')
  end

  def skip_cap!
    pause_terminal!(reason: "outbound_cap_reached:#{MAX_OUTBOUND}")
  end

  def park_until_gap_elapsed!
    due_at = participant.last_outbound_at + MIN_GAP
    participant.update!(next_action_at: due_at)
  end

  # Parks the participant indefinitely while a draft awaits operator
  # review. Setting next_action_at = nil takes the participant out of
  # CampaignParticipant.due_for_tick (the scope filters on
  # `next_action_at <= now`), so the runner stops re-generating drafts
  # every tick. The Outreach::Drafts::ApproveService /
  # RegenerateService / RejectService re-arm next_action_at when the
  # operator acts.
  def park_for_operator!
    metadata = (participant.metadata || {}).merge('parked_for_operator_at' => Time.current.iso8601)
    participant.update!(next_action_at: nil, metadata: metadata)
  end

  def advance_after_send
    if stage.next_stage_key.present?
      transition_to!(stage.next_stage_key)
    else
      pause_terminal!(reason: "send_without_next_stage:#{stage.key}")
    end
    participant.update!(last_outbound_at: Time.current)
  end
end
