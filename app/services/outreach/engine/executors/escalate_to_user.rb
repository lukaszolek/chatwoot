# EscalateToUser executor: assigns the participant's conversation to the
# campaign's sender_user (or leaves it unassigned if none configured) and
# posts a private note flagging the escalation. Pauses the participant
# so the engine no longer advances them — an operator takes over the
# conversation manually from here.
class Outreach::Engine::Executors::EscalateToUser < Outreach::Engine::Executors::Base
  DEFAULT_NOTE = 'Outreach engine escalated this conversation for manual review.'.freeze

  def call
    conversation = participant.conversation
    if conversation
      assign_to_sender(conversation)
      add_private_note(conversation, note_body)
    end

    pause_terminal!(reason: "escalated:#{stage.key}")
  end

  private

  def assign_to_sender(conversation)
    sender = campaign.sender_user
    return unless sender
    return if conversation.assignee_id == sender.id

    conversation.update!(assignee: sender)
  end

  def add_private_note(conversation, body)
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      private: true,
      content: body,
      content_type: 'text'
    )
  end

  def note_body
    metadata = participant.metadata || {}
    reason = metadata['escalation_reason']
    return DEFAULT_NOTE if reason.blank?

    "Outreach engine escalated this conversation — #{reason}"
  end
end
