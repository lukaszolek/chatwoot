# Runs a single outreach engine tick for one campaign. Load via id so
# the job survives a campaign being archived mid-dispatch.
class Outreach::CampaignTickJob < ApplicationJob
  queue_as :outreach

  def perform(campaign_id)
    campaign = OutboundCampaign.find_by(id: campaign_id)
    return unless campaign&.active?

    Outreach::Engine::Runner.new(campaign).tick
  end
end
