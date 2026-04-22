# Outreach engine rake tasks.
#
# Usage:
#   # Apply all YAML blueprints in db/campaign_blueprints/ to a specific account
#   bundle exec rake "outreach:blueprints:apply[ACCOUNT_ID]"
#   ACCOUNT_ID=1 bundle exec rake outreach:blueprints:apply
#
#   # Import photographers from photographer-directory for a given country
#   bundle exec rake "outreach:photographers:import[ACCOUNT_ID,pl]"
#   ACCOUNT_ID=1 COUNTRY=pl bundle exec rake outreach:photographers:import

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

  namespace :photographers do
    desc 'Import photographers from photographer-directory (read + write-limited-scope)'
    task :import, %i[account_id country] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)
      country = args[:country].presence || ENV.fetch('COUNTRY', nil)

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      account = Account.find(account_id)
      result = Outreach::PhotographerDirectory::Importer.new(account: account, country: country).perform

      puts "Import complete for account ##{account.id} country=#{country || 'all'}:"
      puts "  imported=#{result.imported} updated=#{result.updated} " \
           "skipped=#{result.skipped} failed=#{result.failed} (total=#{result.total})"
    end
  end
end
