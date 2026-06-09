class Conversations::GmailArchiveJob < ApplicationJob
  queue_as :scheduled_jobs

  # Archives the given emails in Gmail by removing the \Inbox label via the
  # Gmail-specific X-GM-LABELS IMAP extension. The mail stays in "All Mail"
  # (no deletion). Idempotent: emails no longer in INBOX are skipped.
  def perform(channel, message_ids)
    return if message_ids.blank?

    imap = Conversations::GmailImap.build_client(channel)
    return unless imap

    imap.select('INBOX')
    uids = message_ids.flat_map { |mid| imap.uid_search(['HEADER', 'Message-ID', mid]) }.uniq
    imap.uid_store(uids, '-X-GM-LABELS', [:Inbox]) if uids.any?
  rescue StandardError => e
    Rails.logger.error("[GmailArchive] channel=#{channel.id}: #{e.message}")
  ensure
    Conversations::GmailImap.safe_logout(imap)
  end
end
