# Cron entry-point: fans out CampaignTickJob for every active
# OutboundCampaign. Kept parameterless for the sidekiq-cron
# schedule.yml contract. Run every 5 min (see config/schedule.yml).
class Outreach::TickSchedulerJob < ApplicationJob
  queue_as :outreach

  def perform
    campaign_ids = OutboundCampaign.active.pluck(:id)
    campaign_ids.each { |id| Outreach::CampaignTickJob.perform_later(id) }
    Rails.logger.info("[outreach.tick_scheduler] dispatched #{campaign_ids.size} campaign tick(s)")
  end
end
