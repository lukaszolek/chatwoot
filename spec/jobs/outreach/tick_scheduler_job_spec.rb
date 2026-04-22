# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::TickSchedulerJob do
  describe '#perform' do
    it 'enqueues CampaignTickJob for every active campaign' do
      active_a = create(:outbound_campaign, :active)
      active_b = create(:outbound_campaign, :active, account: active_a.account)
      create(:outbound_campaign, account: active_a.account) # draft — skipped
      create(:outbound_campaign, :active, account: active_a.account, status: :paused).tap { |c| c.update!(status: :paused) }

      expect { described_class.new.perform }
        .to have_enqueued_job(Outreach::CampaignTickJob).exactly(2).times
        .and have_enqueued_job(Outreach::CampaignTickJob).with(active_a.id)
        .and have_enqueued_job(Outreach::CampaignTickJob).with(active_b.id)
    end
  end
end
