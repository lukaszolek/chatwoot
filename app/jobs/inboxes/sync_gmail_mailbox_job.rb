class Inboxes::SyncGmailMailboxJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    accounts_with_gmail.find_each(batch_size: 50) do |account|
      next if account.suspended?

      sync_account(account)
    end
  end

  private

  def accounts_with_gmail
    Account.where(id: gmail_account_ids)
  end

  def gmail_account_ids
    Inbox.where(channel_type: 'Channel::Email')
         .joins('INNER JOIN channel_email ON channel_email.id = inboxes.channel_id')
         .where(channel_email: { imap_enabled: true })
         .where('channel_email.provider = ? OR channel_email.imap_address = ?', 'google', 'imap.gmail.com')
         .distinct
         .pluck(:account_id)
  end

  def sync_account(account)
    Conversations::MailboxSyncService.new(account: account).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Rails.logger.error("[SyncGmailMailboxJob] Account #{account.id} failed: #{e.message}")
  end
end
