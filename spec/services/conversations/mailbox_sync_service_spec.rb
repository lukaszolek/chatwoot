# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::MailboxSyncService do
  describe '#perform' do
    it 'does not overwrite statuses of outreach conversations' do
      account = create(:account)
      channel = create(:channel_email, :imap_email, account: account)
      inbox = channel.inbox
      regular_conversation = create(:conversation, account: account, inbox: inbox, status: :open)
      outreach_conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        status: :open,
        additional_attributes: {
          'outbound_campaign_program_key' => 'photographer_partnership',
          'campaign_participant_id' => 123
        }
      )
      create(:message, account: account, inbox: inbox, conversation: regular_conversation, message_type: :incoming, source_id: 'regular-message-id')
      create(:message, account: account, inbox: inbox, conversation: outreach_conversation, message_type: :incoming, source_id: 'outreach-message-id')

      service = described_class.new(account: account)
      allow(service).to receive(:fetch_inbox_message_ids).and_return(Set.new)
      allow(service).to receive(:messages_present_in_gmail_inbox?)
        .with(regular_conversation, ['regular-message-id'])
        .and_return(false)

      result = service.perform

      expect(result[:resolved]).to eq(1)
      expect(regular_conversation.reload).to be_resolved
      expect(outreach_conversation.reload).to be_open
    end

    it 'keeps an open conversation when the precise Gmail check finds an older incoming message in INBOX' do
      account = create(:account)
      channel = create(:channel_email, :imap_email, account: account)
      inbox = channel.inbox
      conversation = create(:conversation, account: account, inbox: inbox, status: :open)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, source_id: 'old-message-id')

      service = described_class.new(account: account)
      allow(service).to receive(:fetch_inbox_message_ids).and_return(Set.new)
      allow(service).to receive(:messages_present_in_gmail_inbox?)
        .with(conversation, ['old-message-id'])
        .and_return(true)

      result = service.perform

      expect(result[:resolved]).to eq(0)
      expect(conversation.reload).to be_open
    end

    it 'does not resolve conversations that only have outgoing message source ids' do
      account = create(:account)
      channel = create(:channel_email, :imap_email, account: account)
      inbox = channel.inbox
      conversation = create(:conversation, account: account, inbox: inbox, status: :open)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, source_id: 'outgoing-message-id')

      service = described_class.new(account: account)
      allow(service).to receive(:fetch_inbox_message_ids).and_return(Set.new)

      result = service.perform

      expect(result[:resolved]).to eq(0)
      expect(conversation.reload).to be_open
    end

    it 'does not reopen manually labeled outreach conversations' do
      account = create(:account)
      channel = create(:channel_email, :imap_email, account: account)
      inbox = channel.inbox
      auto_reply_conversation = create(:conversation, account: account, inbox: inbox, status: :resolved)
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: auto_reply_conversation,
        source_id: 'auto-reply-message-id'
      )
      auto_reply_conversation.update!(label_list: ['outreach_auto_reply'])
      auto_reply_conversation.resolved!

      service = described_class.new(account: account)
      allow(service).to receive(:fetch_inbox_message_ids).and_return(Set.new(['auto-reply-message-id']))

      result = service.perform

      expect(result[:archived]).to eq(0)
      expect(auto_reply_conversation.reload).to be_resolved
    end
  end
end
