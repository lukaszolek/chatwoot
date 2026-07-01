# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhotographerPartnerProfile do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:contact).optional }
  end

  describe 'validations' do
    subject { build(:photographer_partner_profile) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_uniqueness_of(:external_id).scoped_to(:account_id) }
  end

  describe 'partnership_status enum' do
    it 'exposes the full partnership lifecycle' do
      expect(described_class.partnership_statuses.keys).to eq(
        %w[imported qualified contacted replied interested signed_up declined do_not_contact completed]
      )
    end
  end

  describe '.active_outreach' do
    it 'excludes do_not_contact and completed profiles' do
      imported = create(:photographer_partner_profile, partnership_status: :imported)
      create(:photographer_partner_profile, partnership_status: :do_not_contact)
      create(:photographer_partner_profile, partnership_status: :completed)

      expect(described_class.active_outreach).to contain_exactly(imported)
    end
  end

  describe '#pipeline_stage' do
    it 'exposes do_not_contact as the opt-out pipeline stage' do
      profile = described_class.new(partnership_status: :do_not_contact)

      expect(profile.pipeline_stage).to eq('do_not_contact')
    end
  end

  describe '#transition_to!' do
    it 'updates status and stamps the transition time' do
      profile = create(:photographer_partner_profile, partnership_status: :imported, partnership_status_changed_at: nil)

      freeze_time do
        profile.transition_to!(:contacted)
        expect(profile.reload).to have_attributes(
          partnership_status: 'contacted',
          partnership_status_changed_at: Time.current
        )
      end
    end
  end
end
