# Cron entry-point: fans out `SyncJob` for every account that has an
# active outbound campaign for the photographer_partnership program.
# Kept parameterless so it fits the sidekiq-cron schedule.yml contract.
class Outreach::PhotographerDirectory::ScheduledSyncJob < ApplicationJob
  queue_as :outreach

  PROGRAM_KEY = 'photographer_partnership'.freeze

  def perform
    account_ids = OutboundCampaign.active.where(program_key: PROGRAM_KEY).distinct.pluck(:account_id)
    account_ids.each { |id| Outreach::PhotographerDirectory::SyncJob.perform_later(id) }
    Rails.logger.info("[outreach.sync] scheduled #{account_ids.size} account(s) for import")
  end
end
