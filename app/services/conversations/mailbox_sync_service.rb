class Conversations::MailboxSyncService
  def initialize(account:)
    @account = account
  end

  def perform
    channels = google_email_channels
    return { resolved: 0, checked: 0, error: 'No Google email channels found' } if channels.empty?

    inbox_emails = fetch_inbox_emails(channels)
    return { resolved: 0, checked: 0, error: 'Could not connect to mailbox' } if inbox_emails.nil?

    resolve_archived_conversations(inbox_emails)
  end

  private

  def google_email_channels
    Channel::Email
      .where(provider: 'google', imap_enabled: true)
      .joins(:inbox)
      .where(inboxes: { account_id: @account.id })
      .includes(:inbox)
  end

  def fetch_inbox_emails(channels)
    all_emails = Set.new

    channels.each do |channel|
      emails = fetch_channel_inbox_emails(channel)
      all_emails.merge(emails) if emails
    end

    all_emails
  rescue StandardError => e
    Rails.logger.error("[MailboxSync] IMAP error: #{e.message}")
    nil
  end

  def fetch_channel_inbox_emails(channel)
    return nil if channel.provider_config['access_token'].blank?

    access_token = Google::RefreshOauthTokenService.new(channel: channel).access_token
    imap = Net::IMAP.new('imap.gmail.com', port: 993, ssl: true)
    imap.authenticate('XOAUTH2', channel.imap_login, access_token)
    imap.select('INBOX')

    since_date = 30.days.ago.strftime('%d-%b-%Y')
    uids = imap.uid_search(['SINCE', since_date])

    return Set.new if uids.empty?

    emails = Set.new
    uids.each_slice(100) do |batch|
      envelopes = imap.uid_fetch(batch, 'ENVELOPE')
      envelopes&.each do |msg|
        envelope = msg.attr['ENVELOPE']
        (envelope.from || []).each do |addr|
          email = "#{addr.mailbox}@#{addr.host}".downcase
          emails.add(email)
        end
      end
    end

    emails
  ensure
    imap&.logout
    imap&.disconnect
  end

  def resolve_archived_conversations(inbox_emails)
    open_email_conversations = @account.conversations
                                       .where(status: %i[open pending])
                                       .where(inbox_id: email_inbox_ids)
                                       .joins(:contact)
                                       .where.not(contacts: { email: [nil, ''] })
                                       .includes(:contact)
    checked = 0
    resolved = 0

    open_email_conversations.find_each do |conversation|
      contact_email = conversation.contact.email.downcase
      checked += 1

      next if inbox_emails.include?(contact_email)

      conversation.update!(status: :resolved)
      resolved += 1
    end

    { resolved: resolved, checked: checked }
  end

  def email_inbox_ids
    @email_inbox_ids ||= @account.inboxes.where(channel_type: 'Channel::Email').pluck(:id)
  end
end
