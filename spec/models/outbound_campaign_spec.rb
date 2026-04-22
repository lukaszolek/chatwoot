# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OutboundCampaign do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:inbox).optional }
    it { is_expected.to belong_to(:sender_user).class_name('User').optional }
    it { is_expected.to have_many(:pipeline_stages).class_name('CampaignPipelineStage').dependent(:destroy) }
    it { is_expected.to have_many(:templates).class_name('CampaignTemplate').dependent(:destroy) }
    it { is_expected.to have_many(:participants).class_name('CampaignParticipant').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:outbound_campaign) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:program_key) }
    it { is_expected.to validate_uniqueness_of(:program_key).scoped_to(:account_id) }
  end

  describe 'status enum' do
    it 'exposes the expected states' do
      expect(described_class.statuses).to eq('draft' => 0, 'active' => 1, 'paused' => 2, 'archived' => 3)
    end
  end

  describe '.runnable' do
    it 'returns only active campaigns' do
      create(:outbound_campaign, status: :draft)
      active = create(:outbound_campaign, :active)

      expect(described_class.runnable).to contain_exactly(active)
    end
  end

  describe 'program_key scoping' do
    it 'allows the same program_key across different accounts' do
      create(:outbound_campaign, program_key: 'photographer_partnership')
      other_account_campaign = build(:outbound_campaign, program_key: 'photographer_partnership')

      expect(other_account_campaign).to be_valid
    end
  end
end
