class GmailMailboxListener < BaseListener
  # When a Gmail-channel conversation is resolved in Chatwoot, archive its
  # emails in Gmail (remove them from INBOX). The periodic SyncGmailMailboxJob
  # acts as a safety net for resolves that miss this event.
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    return unless gmail_imap_conversation?(conversation)
    return if Outreach::ConversationLabels.outreach_conversation?(conversation)

    message_ids = conversation.messages.where.not(source_id: nil).pluck(:source_id)
    return if message_ids.blank?

    Conversations::GmailArchiveJob.perform_later(conversation.inbox.channel, message_ids)
  end

  private

  def gmail_imap_conversation?(conversation)
    channel = conversation.inbox.channel
    return false unless channel.is_a?(Channel::Email)

    (channel.google? && channel.imap_enabled?) || channel.legacy_google?
  end
end
