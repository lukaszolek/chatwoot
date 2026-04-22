# Outreach engine rake tasks.
#
# Usage:
#   # Apply all YAML blueprints in db/campaign_blueprints/ to a specific account
#   bundle exec rake "outreach:blueprints:apply[ACCOUNT_ID]"
#
#   # Or via env var (shell-friendly)
#   ACCOUNT_ID=1 bundle exec rake outreach:blueprints:apply

namespace :outreach do
  namespace :blueprints do
    desc 'Apply all campaign blueprints in db/campaign_blueprints/ to an account'
    task :apply, [:account_id] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      account = Account.find(account_id)
      applied = Outreach::BlueprintApplier.apply_all(account: account)

      puts "Applied #{applied.size} blueprint(s) to account ##{account.id} (#{account.name}):"
      applied.each do |campaign|
        puts "  - #{campaign.program_key} (#{campaign.pipeline_stages.count} stages, " \
             "#{campaign.templates.active_templates.count} active templates)"
      end
    end
  end
end
