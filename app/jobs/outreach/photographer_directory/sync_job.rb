# Pulls fresh photographer leads from the photographer-directory secondary
# DB into chatwoot. Scheduled every 6h via sidekiq-cron. Safe to trigger
# manually (e.g., from a rake task or admin console) because the
# underlying importer is idempotent.
class Outreach::PhotographerDirectory::SyncJob < ApplicationJob
  queue_as :outreach

  def perform(account_id, country: nil)
    account = Account.find(account_id)
    result = Outreach::PhotographerDirectory::Importer.new(account: account, country: country).perform

    Rails.logger.info(
      "[outreach.sync] account=#{account.id} country=#{country || 'all'} " \
      "imported=#{result.imported} updated=#{result.updated} " \
      "skipped=#{result.skipped} failed=#{result.failed}"
    )

    result
  end
end
