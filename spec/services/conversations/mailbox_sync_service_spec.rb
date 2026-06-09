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
      create(:message, account: account, inbox: inbox, conversation: regular_conversation, source_id: 'regular-message-id')
      create(:message, account: account, inbox: inbox, conversation: outreach_conversation, source_id: 'outreach-message-id')

      service = described_class.new(account: account)
      allow(service).to receive(:fetch_inbox_message_ids).and_return(Set.new)

      result = service.perform

      expect(result[:resolved]).to eq(1)
      expect(regular_conversation.reload).to be_resolved
      expect(outreach_conversation.reload).to be_open
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
