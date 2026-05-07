class SyncGmailMailboxesOnDeploy < ActiveRecord::Migration[7.0]
  def up
    return if Rails.env.test?

    # Reconcile every connected Gmail mailbox once at deploy time so that:
    # - sent items already in [Gmail]/Sent Mail get imported as outgoing messages
    # - conversations whose threads were archived in Gmail flip to :resolved
    # - conversations whose threads are back in INBOX flip to :open
    # The same logic also runs every minute (FetchImapEmailsJob) and every 5 minutes
    # (SyncGmailMailboxJob) post-deploy; this is just the initial backfill,
    # using a wider 14-day interval to catch older sent items.

    enqueue_fetch_for_each_gmail_channel
    Inboxes::SyncGmailMailboxJob.perform_later
  end

  def down
    # No-op: enqueueing jobs is not reversible.
  end

  private

  def enqueue_fetch_for_each_gmail_channel
    Channel::Email
      .where(imap_enabled: true)
      .where('provider = ? OR imap_address = ?', 'google', 'imap.gmail.com')
      .find_each(batch_size: 100) do |channel|
        next if channel.reauthorization_required?
        next if channel.account.suspended?

        Inboxes::FetchImapEmailsJob.perform_later(channel, 14)
      end
  end
end
