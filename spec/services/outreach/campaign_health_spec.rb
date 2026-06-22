require 'rails_helper'
require 'securerandom'

RSpec.describe Outreach::CampaignHealth do
  describe '#summary' do
    let(:campaign) { create(:outbound_campaign, :active, :photographer_partnership) }

    it 'counts only active intro participants without a conversation and with an existing profile' do
      valid_profile = create_profile(campaign.account)
      orphan_profile = create_profile(campaign.account)
      paused_profile = create_profile(campaign.account)
      connected_profile = create_profile(campaign.account)

      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: valid_profile,
        current_stage_key: 'intro',
        paused: false,
        conversation_id: nil
      )

      orphan_participant = create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: orphan_profile,
        current_stage_key: 'intro',
        paused: false,
        conversation_id: nil
      )
      orphan_profile.destroy!

      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: paused_profile,
        current_stage_key: 'intro',
        paused: true,
        conversation_id: nil
      )

      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: connected_profile,
        current_stage_key: 'intro',
        paused: false,
        conversation: create(:conversation, account: campaign.account)
      )

      expect(orphan_participant.reload.participatable).to be_nil
      expect(described_class.new(campaign).summary[:missing_drafts_count]).to eq(1)
    end

    def create_profile(account)
      PhotographerPartnerProfile.create!(
        account: account,
        external_id: SecureRandom.hex(8)
      )
    end
  end
end
