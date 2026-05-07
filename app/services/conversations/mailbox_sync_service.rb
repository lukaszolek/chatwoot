class Conversations::MailboxSyncService
  SINCE_DAYS = 14
  BATCH_SIZE = 200

  def initialize(account:)
    @account = account
  end

  def perform
    channels = gmail_channels
    return { resolved: 0, reopened: 0, checked: 0, error: 'No Gmail channels found' } if channels.empty?

    inbox_message_ids = fetch_inbox_message_ids(channels)
    return { resolved: 0, reopened: 0, checked: 0, error: 'Could not connect to mailbox' } if inbox_message_ids.nil?

    sync_conversation_statuses(inbox_message_ids)
  end

  private

  def gmail_channels
    Channel::Email
      .where(imap_enabled: true)
      .where('provider = ? OR imap_address = ?', 'google', 'imap.gmail.com')
      .joins(:inbox)
      .where(inboxes: { account_id: @account.id })
      .includes(:inbox)
  end

  def fetch_inbox_message_ids(channels)
    all_ids = Set.new

    channels.each do |channel|
      ids = fetch_channel_inbox_message_ids(channel)
      all_ids.merge(ids) if ids
    end

    all_ids
  rescue StandardError => e
    Rails.logger.error("[MailboxSync] IMAP error: #{e.message}")
    nil
  end

  def fetch_channel_inbox_message_ids(channel)
    imap = build_imap_client(channel)
    return nil unless imap

    imap.select('INBOX')
    seq_nums = imap.search(['SINCE', SINCE_DAYS.days.ago.strftime('%d-%b-%Y')])
    return Set.new if seq_nums.empty?

    collect_message_ids(imap, seq_nums)
  ensure
    safe_logout(imap)
  end

  def collect_message_ids(imap, seq_nums)
    ids = Set.new
    seq_nums.each_slice(100) do |batch|
      headers = imap.fetch(batch, 'BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)]')
      headers&.each do |data|
        raw = data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]']
        next if raw.blank?

        message_id = Mail.read_from_string(raw).message_id
        ids.add(message_id) if message_id.present?
      end
    end
    ids
  end

  def build_imap_client(channel)
    if channel.provider == 'google' && channel.provider_config.is_a?(Hash) && channel.provider_config['access_token'].present?
      access_token = Google::RefreshOauthTokenService.new(channel: channel).access_token
      imap = Net::IMAP.new('imap.gmail.com', port: 993, ssl: true)
      imap.authenticate('XOAUTH2', channel.imap_login.presence || channel.email, access_token)
    elsif channel.imap_password.present?
      imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: true)
      imap.authenticate('PLAIN', channel.imap_login, channel.imap_password)
    else
      return nil
    end
    imap
  end

  def safe_logout(imap)
    return unless imap

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end

  def sync_conversation_statuses(inbox_message_ids)
    checked = 0
    resolved = 0
    reopened = 0

    candidate_conversations.find_each(batch_size: BATCH_SIZE) do |conversation|
      checked += 1
      source_ids = conversation.messages.where.not(source_id: nil).pluck(:source_id)
      thread_in_inbox = source_ids.any? { |sid| inbox_message_ids.include?(sid) }

      if (conversation.open? || conversation.pending?) && !thread_in_inbox
        conversation.update!(status: :resolved)
        resolved += 1
      elsif conversation.resolved? && thread_in_inbox
        conversation.update!(status: :open)
        reopened += 1
      end
    end

    { resolved: resolved, reopened: reopened, checked: checked }
  end

  def candidate_conversations
    @account.conversations
            .where(status: %i[open pending resolved])
            .where(inbox_id: gmail_inbox_ids)
            .where("COALESCE(conversations.additional_attributes->>'outbound_campaign_program_key', '') = ''")
            .where("COALESCE(conversations.additional_attributes->>'campaign_participant_id', '') = ''")
  end

  def gmail_inbox_ids
    @gmail_inbox_ids ||= gmail_channels.map(&:inbox).map(&:id)
  end
end
