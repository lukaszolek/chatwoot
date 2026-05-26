# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Drafts::BulkApproveService do
  describe '#call' do
    it 'approves pending intro drafts even when the conversation is resolved' do
      account = create(:account)
      user = create(:user, account: account)
      campaign = create(:outbound_campaign, :photographer_partnership, account: account)
      contact = create(:contact, account: account)
      participant = create(:campaign_participant, account: account, outbound_campaign: campaign, participatable: contact)
      conversation = create(
        :conversation,
        account: account,
        additional_attributes: {
          'outbound_campaign_id' => campaign.id,
          'outbound_campaign_program_key' => campaign.program_key,
          'campaign_participant_id' => participant.id
        }
      )
      participant.update!(conversation: conversation)
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Intro body with STOP opt-out',
        content_attributes: { email: { subject: 'Intro subject' } },
        additional_attributes: {
          'outreach_draft' => true,
          'draft_status' => 'pending',
          'template_slot' => 'intro',
          'outbound_campaign_id' => campaign.id,
          'campaign_participant_id' => participant.id
        }
      )
      conversation.resolved!

      result = described_class.new(campaign: campaign, user: user, limit: 10).call

      expect(result.selected).to eq(1)
      expect(result.approved).to eq(1)
    end

    it 'discards a pending reminder when a real reply arrived after the intro' do
      account = create(:account)
      user = create(:user, account: account)
      campaign = create(:outbound_campaign, :photographer_partnership, account: account)
      contact = create(:contact, account: account)
      participant = create(:campaign_participant, account: account, outbound_campaign: campaign, participatable: contact)
      conversation = create(
        :conversation,
        account: account,
        contact: contact,
        additional_attributes: {
          'outbound_campaign_id' => campaign.id,
          'outbound_campaign_program_key' => campaign.program_key,
          'campaign_participant_id' => participant.id
        }
      )
      participant.update!(conversation: conversation)
      create_public_outreach_message!(account, conversation, participant, 2.days.ago)
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :incoming,
        private: false,
        content: 'Dzień dobry, proszę o więcej informacji.',
        created_at: 1.day.ago
      )
      draft = create_reminder_draft!(account, conversation, campaign, participant)

      result = described_class.new(campaign: campaign, user: user, limit: 10, template_slot: 'reminder').call

      expect(result.selected).to eq(1)
      expect(result.approved).to eq(0)
      expect(result.stale_skipped).to eq(1)
      expect(draft.reload.outreach_draft_status).to eq('discarded')
      expect(draft.additional_attributes['discarded_reason']).to eq('stale_inbound_before_bulk_approve')
    end

    it 'approves a pending reminder when only an auto-reply arrived after the intro' do
      account = create(:account)
      user = create(:user, account: account)
      campaign = create(:outbound_campaign, :photographer_partnership, account: account)
      contact = create(:contact, account: account)
      participant = create(:campaign_participant, account: account, outbound_campaign: campaign, participatable: contact)
      conversation = create(
        :conversation,
        account: account,
        contact: contact,
        additional_attributes: {
          'outbound_campaign_id' => campaign.id,
          'outbound_campaign_program_key' => campaign.program_key,
          'campaign_participant_id' => participant.id
        }
      )
      participant.update!(conversation: conversation)
      create_public_outreach_message!(account, conversation, participant, 2.days.ago)
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :incoming,
        private: false,
        content: 'Automatic reply: I am out of office.',
        created_at: 1.day.ago
      )
      draft = create_reminder_draft!(account, conversation, campaign, participant)

      result = described_class.new(campaign: campaign, user: user, limit: 10, template_slot: 'reminder').call

      expect(result.selected).to eq(1)
      expect(result.approved).to eq(1)
      expect(result.stale_skipped).to eq(0)
      expect(draft.reload.outreach_draft_status).to eq('approved')
    end
  end

  def create_public_outreach_message!(account, conversation, participant, created_at)
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: false,
      content: 'Intro sent',
      created_at: created_at,
      additional_attributes: {
        'outreach' => {
          'campaign_participant_id' => participant.id,
          'outbound_campaign_id' => participant.outbound_campaign_id,
          'template_slot' => 'intro'
        }
      }
    )
  end

  def create_reminder_draft!(account, conversation, campaign, participant)
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: true,
      content: 'Reminder body with STOP opt-out',
      content_attributes: { email: { subject: 'Reminder subject' } },
      additional_attributes: {
        'outreach_draft' => true,
        'draft_status' => 'pending',
        'template_slot' => 'reminder',
        'locale' => 'pl',
        'outbound_campaign_id' => campaign.id,
        'campaign_participant_id' => participant.id
      }
    )
  end
end
