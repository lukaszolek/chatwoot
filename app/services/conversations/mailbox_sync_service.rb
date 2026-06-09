class Conversations::MailboxSyncService
  SINCE_DAYS = 14
  BATCH_SIZE = 200

  def initialize(account:)
    @account = account
  end

  def perform
    channels = gmail_channels
    return { resolved: 0, archived: 0, checked: 0, error: 'No Gmail channels found' } if channels.empty?

    inbox_message_ids = fetch_inbox_message_ids(channels)
    return { resolved: 0, archived: 0, checked: 0, error: 'Could not connect to mailbox' } if inbox_message_ids.nil?

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
    imap = Conversations::GmailImap.build_client(channel)
    return nil unless imap

    imap.select('INBOX')
    seq_nums = imap.search(['SINCE', SINCE_DAYS.days.ago.strftime('%d-%b-%Y')])
    return Set.new if seq_nums.empty?

    collect_message_ids(imap, seq_nums)
  ensure
    Conversations::GmailImap.safe_logout(imap)
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

  def sync_conversation_statuses(inbox_message_ids)
    stats = { resolved: 0, archived: 0, checked: 0 }
    archive_targets = Hash.new { |hash, key| hash[key] = [] }

    candidate_conversations.find_each(batch_size: BATCH_SIZE) do |conversation|
      stats[:checked] += 1
      action = reconcile_conversation(conversation, inbox_message_ids, archive_targets)
      stats[action] += 1 if action
    end

    enqueue_archive(archive_targets)
    stats
  end

  def reconcile_conversation(conversation, inbox_message_ids, archive_targets)
    source_ids = conversation.messages.where.not(source_id: nil).pluck(:source_id)
    in_inbox_ids = source_ids.select { |sid| inbox_message_ids.include?(sid) }

    if needs_resolve?(conversation, in_inbox_ids)
      conversation.update!(status: :resolved)
      :resolved
    elsif needs_archive?(conversation, in_inbox_ids)
      enqueue_for_archive(conversation, in_inbox_ids, archive_targets)
    end
  end

  def needs_resolve?(conversation, in_inbox_ids)
    (conversation.open? || conversation.pending?) && in_inbox_ids.empty?
  end

  def needs_archive?(conversation, in_inbox_ids)
    conversation.resolved? && in_inbox_ids.any?
  end

  def enqueue_for_archive(conversation, in_inbox_ids, archive_targets)
    channel = channel_for(conversation)
    return unless channel

    archive_targets[channel].concat(in_inbox_ids)
    :archived
  end

  def channel_for(conversation)
    channel_by_inbox_id[conversation.inbox_id]
  end

  def channel_by_inbox_id
    @channel_by_inbox_id ||= gmail_channels.index_by { |channel| channel.inbox.id }
  end

  def enqueue_archive(archive_targets)
    archive_targets.each do |channel, message_ids|
      Conversations::GmailArchiveJob.perform_later(channel, message_ids.uniq)
    end
  end

  def candidate_conversations
    @account.conversations
            .where(status: %i[open pending resolved])
            .where(inbox_id: gmail_inbox_ids)
            .where("COALESCE(conversations.additional_attributes->>'outbound_campaign_program_key', '') = ''")
            .where("COALESCE(conversations.additional_attributes->>'campaign_participant_id', '') = ''")
            .where.not("COALESCE(conversations.cached_label_list, '') ~ ?", outreach_label_pattern)
            .where.not(id: outreach_labeled_conversations)
  end

  def gmail_inbox_ids
    @gmail_inbox_ids ||= gmail_channels.map(&:inbox).map(&:id)
  end

  def outreach_labeled_conversations
    @outreach_labeled_conversations ||= @account.conversations
                                                .tagged_with(Outreach::ConversationLabels::LABELS.values, any: true)
                                                .distinct
                                                .pluck(:id)
  end

  def outreach_label_pattern
    @outreach_label_pattern ||= Outreach::ConversationLabels::LABELS.values.join('|')
  end
end
