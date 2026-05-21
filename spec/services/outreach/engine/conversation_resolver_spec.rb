# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::ConversationResolver do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) do
    create(:outbound_campaign,
           :photographer_partnership,
           account: account,
           inbox: inbox)
  end
  let(:contact) { create(:contact, :with_email, account: account, email: 'studio@example.com') }
  let(:profile) do
    PhotographerPartnerProfile.create!(
      account: account,
      contact: contact,
      external_id: 'directory-123',
      partnership_status: :imported
    )
  end
  let(:participant) do
    create(:campaign_participant,
           account: account,
           outbound_campaign: campaign,
           participatable: profile,
           contact: contact,
           conversation: nil)
  end

  describe '#conversation' do
    it 'reuses an existing campaign conversation for the same contact and inbox' do
      existing = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        additional_attributes: {
          'outbound_campaign_id' => campaign.id,
          'outbound_campaign_program_key' => campaign.program_key
        }
      )

      conversation = described_class.new(participant).conversation

      expect(conversation).to eq(existing)
      expect(participant.reload.conversation).to eq(existing)
      expect(existing.reload.additional_attributes).to include(
        'campaign_participant_id' => participant.id,
        'outbound_campaign_id' => campaign.id,
        'outbound_campaign_program_key' => campaign.program_key
      )
    end
  end
end
