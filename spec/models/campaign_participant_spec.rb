# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CampaignParticipant do
  describe 'associations' do
    it { is_expected.to belong_to(:outbound_campaign) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:participatable) }
    it { is_expected.to belong_to(:conversation).optional }
    it { is_expected.to belong_to(:contact).optional }
    it { is_expected.to have_many(:llm_decisions).class_name('CampaignLlmDecision').dependent(:destroy) }
  end

  describe 'uniqueness of participatable per campaign' do
    let(:campaign) { create(:outbound_campaign) }
    let(:profile) { create(:photographer_partner_profile, account: campaign.account) }

    it 'allows one participant per (campaign, participatable)' do
      create(:campaign_participant, outbound_campaign: campaign, participatable: profile, account: campaign.account)

      duplicate = build(:campaign_participant, outbound_campaign: campaign, participatable: profile, account: campaign.account)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:outbound_campaign_id]).to be_present
    end

    it 'allows the same profile in a different campaign' do
      other_campaign = create(:outbound_campaign, account: campaign.account)
      create(:campaign_participant, outbound_campaign: campaign, participatable: profile, account: campaign.account)

      second = build(:campaign_participant, outbound_campaign: other_campaign, participatable: profile, account: campaign.account)

      expect(second).to be_valid
    end
  end

  describe '.due_for_tick' do
    it 'includes participants whose next_action_at has passed and are not paused' do
      due = create(:campaign_participant, next_action_at: 1.minute.ago, paused: false)
      create(:campaign_participant, next_action_at: 1.hour.from_now, paused: false)
      create(:campaign_participant, next_action_at: 1.minute.ago, paused: true)

      expect(described_class.due_for_tick).to contain_exactly(due)
    end
  end
end
