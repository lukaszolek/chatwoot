# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Drafts::DiscardPendingConversationDraftsService do
  describe '#call' do
    it 'discards all pending outreach drafts in the conversation and clears the draft label' do
      account = create(:account)
      user = create(:user, account: account)
      conversation = create(:conversation, account: account)

      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Draft 1',
        additional_attributes: {
          'outreach_draft' => true,
          'draft_status' => 'pending',
          'template_slot' => 'intro'
        }
      )
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Draft 2',
        additional_attributes: {
          'outreach_draft' => true,
          'draft_status' => 'pending',
          'template_slot' => 'reminder'
        }
      )

      conversation.reload
      expect(conversation.label_list).to include('outreach_draft')

      result = described_class.new(
        conversation: conversation,
        user: user,
        reason: 'spec_cleanup'
      ).call

      expect(result).to eq(2)
      expect(conversation.messages.pending_outreach_drafts.count).to eq(0)
      expect(conversation.messages.outreach_drafts.pluck(Arel.sql("additional_attributes->>'draft_status'"))).to all(eq('discarded'))
      expect(conversation.reload.label_list).not_to include('outreach_draft')
    end
  end
end
