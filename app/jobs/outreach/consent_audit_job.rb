# Sidekiq-cron entrypoint for the daily consent audit (04:00 UTC).
# Thin wrapper over Outreach::ConsentAudit.run! — returns a summary hash
# for metrics ingestion.
class Outreach::ConsentAuditJob < ApplicationJob
  queue_as :outreach

  def perform
    summary = Outreach::ConsentAudit.run!
    Rails.logger.info("[outreach.consent_audit] summary=#{summary.inspect}")
    summary
  end
end
