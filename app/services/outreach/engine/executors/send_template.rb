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

  def call
    return if halt_for_pacing_guard!

    composer_class = composer_class_for_stage
    return unless composer_class

    return if park_existing_manual_review_draft

    composed = composer_class.new(participant: participant).call
    log_decision!(composed)

    conversation = Outreach::Engine::ConversationResolver.new(participant).conversation
    deliver_or_create_draft!(conversation, composed)
  end

  private

  def halt_for_pacing_guard!
    return skip_replied! if already_replied?
    return skip_cap! if outbound_count >= MAX_OUTBOUND
    return park_until_gap_elapsed! if gap_not_elapsed?

    false
  end

  def composer_class_for_stage
    COMPOSERS[stage.template_slot].tap do |composer_class|
      pause_terminal!(reason: "no_composer_for_slot:#{stage.template_slot}") unless composer_class
    end
  end

  def park_existing_manual_review_draft
    return false unless campaign.manual_review_mode?
    return false if pending_draft_for_current_stage.blank?

    park_for_operator!
  end

  def deliver_or_create_draft!(conversation, composed)
    if campaign.manual_review_mode?
      create_or_reuse_outreach_draft_message!(conversation, composed)
    else
      enqueue_send_email!(conversation, composed)
      advance_after_send
    end
  end

  def create_or_reuse_outreach_draft_message!(conversation, composed)
    participant.with_lock do
      existing_draft = pending_draft_for_current_stage
      if existing_draft
        park_for_operator!
        existing_draft
      else
        message = create_outreach_draft_message!(conversation, composed)
        park_for_operator!
        message
      end
    end
  end

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
      additional_attributes: outreach_draft_attributes(composed)
    )
    Outreach::TranslateForAgents.call(message: message, source_locale: composed[:locale])
    message
  end

  def outreach_draft_attributes(composed)
    {
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
  end

  def enqueue_send_email!(conversation, composed)
    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: conversation.id,
      subject: composed[:subject],
      body: composed[:body],
      template_slot: stage.template_slot,
      locale: composed[:locale]
    )
  end

  def pending_draft_for_current_stage
    Message.pending_outreach_drafts.find_by(
      "additional_attributes->>'campaign_participant_id' = ? AND additional_attributes->>'template_slot' = ?",
      participant.id.to_s,
      stage.template_slot.to_s
    )
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
