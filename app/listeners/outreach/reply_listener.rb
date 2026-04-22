# Listens for `message.created` events and routes inbound replies on
# campaign-linked conversations back into the outreach engine.
#
# When an inbound (incoming) message lands on a conversation whose
# additional_attributes carry `campaign_participant_id`, the matching
# CampaignParticipant is flipped into `reply_router` and marked due now.
# The next Runner#tick classifies the reply and dispatches via
# branch_rules.
#
# Outgoing messages, private notes, and activity messages are ignored.
# Terminal participants (paused) are ignored — the engine does not
# re-animate them from a late reply.
class Outreach::ReplyListener < BaseListener
  REPLY_ROUTER_STAGE_KEY = 'reply_router'.freeze

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless reply_message?(message)

    participant_id = participant_id_for(message)
    return unless participant_id

    participant = CampaignParticipant.find_by(id: participant_id)
    return unless participant
    return if participant.paused?

    participant.update!(
      current_stage_key: REPLY_ROUTER_STAGE_KEY,
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      last_inbound_at: Time.current
    )

    Rails.logger.info(
      "[outreach.reply_listener] participant=#{participant.id} conversation=#{message.conversation_id} " \
      "routed=reply_router message=#{message.id}"
    )
  end

  private

  def reply_message?(message)
    return false unless message
    return false unless message.incoming?
    return false if message.private?

    true
  end

  def participant_id_for(message)
    conversation = message.conversation
    return nil unless conversation

    conversation.additional_attributes.to_h['campaign_participant_id']
  end
end
