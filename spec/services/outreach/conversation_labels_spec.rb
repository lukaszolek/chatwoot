# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::ConversationLabels do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, label_list: %w[outreach_replied outreach_auto_reply outreach_error]) }

  describe '.mark_sent!' do
    it 'removes replied, auto_reply, and error labels while marking the conversation as sent' do
      described_class.mark_sent!(conversation)

      expect(conversation.reload.label_list).to include('outreach_sent')
      expect(conversation.label_list).not_to include('outreach_replied', 'outreach_auto_reply', 'outreach_error')
      expect(conversation.status).to eq('pending')
    end
  end
end
