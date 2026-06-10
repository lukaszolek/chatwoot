class Conversations::GmailArchiveJob < ApplicationJob
  queue_as :scheduled_jobs

  # Archives the given emails in Gmail by moving them out of INBOX into "All Mail".
  # The mail is preserved in "All Mail" — never deleted. Idempotent: emails no
  # longer in INBOX are skipped.
  #
  # NOTE: removing the \Inbox label via `-X-GM-LABELS` does NOT remove the message
  # from the IMAP INBOX folder on Gmail, so we move it to All Mail instead.
  def perform(channel, message_ids)
    return if message_ids.blank?

    imap = Conversations::GmailImap.build_client(channel)
    return unless imap

    imap.select('INBOX')
    uids = message_ids.flat_map { |mid| imap.uid_search(['HEADER', 'Message-ID', mid]) }.uniq
    imap.uid_move(uids, all_mail_mailbox(imap)) if uids.any?
  rescue StandardError => e
    Rails.logger.error("[GmailArchive] channel=#{channel.id}: #{e.message}")
  ensure
    Conversations::GmailImap.safe_logout(imap)
  end

  private

  # Resolves Gmail's "All Mail" folder via its \All special-use attribute
  # (resilient to localized folder names), falling back to the default name.
  def all_mail_mailbox(imap)
    imap.list('', '*')&.find { |box| box.attr.include?(:All) }&.name || '[Gmail]/All Mail'
  end
end
