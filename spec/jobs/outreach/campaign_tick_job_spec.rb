# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::CampaignTickJob do
  describe '#perform' do
    it 'runs Runner#tick on an active campaign' do
      campaign = create(:outbound_campaign, :active)
      runner = instance_double(Outreach::Engine::Runner, tick: 3)
      expect(Outreach::Engine::Runner).to receive(:new).with(an_instance_of(OutboundCampaign)).and_return(runner)

      described_class.new.perform(campaign.id)
    end

    it 'is a no-op for a paused campaign' do
      campaign = create(:outbound_campaign, :active)
      campaign.update!(status: :paused)
      expect(Outreach::Engine::Runner).not_to receive(:new)

      described_class.new.perform(campaign.id)
    end

    it 'is a no-op for a missing campaign id' do
      expect(Outreach::Engine::Runner).not_to receive(:new)
      described_class.new.perform(0)
    end
  end
end
