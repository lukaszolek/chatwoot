# Read-only reconciliation of Django partnership registrations against the
# Chatwoot outreach pipeline. For each photographer registered in the
# Django backend within the lookback window, classifies whether they
# appear as "Zarejestrowany" (signed_up) in Chatwoot and why not.
#
# Source-of-truth ordering for matching:
#   L1: email     — case-insensitive on photographer_directory.email
#   L2: website   — normalized host on photographer_directory.website
#   L3: slug      — case-insensitive on photographer_directory.slug
#
# Usage:
#   bundle exec rake "outreach:reconcile_signups[14]"
#   FRAMI_COMPOSER_ENV=/path/to/.env bundle exec rake outreach:reconcile_signups
#
# Output:
#   CSV → tmp/outreach_reconciliation_<timestamp>.csv
#   Summary counts → stdout

require 'csv'
require 'uri'

namespace :outreach do
  desc 'Compare Django registrations vs Chatwoot signed_up profiles (read-only diagnostic)'
  task :reconcile_signups, [:days] => :environment do |_t, args|
    days = (args[:days].presence || ENV.fetch('DAYS', '14')).to_i

    Outreach::Reconciliation::SignupReporter.new(days: days).run
  end
end

module Outreach
  module Reconciliation
    # rubocop:disable Metrics/ClassLength
    class SignupReporter
      DEFAULT_ENV_PATH = File.expand_path('~/Development/framky/frami-composer/.env').freeze
      DJANGO_CONNECTION_NAME = 'framky_django'.freeze

      # Django PartnerStatus enum — registered partnerships only.
      PARTNER_STATUS_PENDING = 1
      PARTNER_STATUS_ACTIVE = 2
      REGISTERED_STATUSES = [PARTNER_STATUS_PENDING, PARTNER_STATUS_ACTIVE].freeze
      PARTNER_STATUS_LABELS = {
        0 => 'NOT_APPLIED', 1 => 'PENDING', 2 => 'ACTIVE',
        3 => 'SUSPENDED', 4 => 'DECLINED'
      }.freeze

      BUCKETS = %w[
        OK_SIGNED_UP
        PROFILE_WRONG_STATUS
        PROFILE_MISSING_DIRECTORY_OK
        DIRECTORY_MISSING
        EMAIL_MISMATCH
        AMBIGUOUS
      ].freeze

      def initialize(days:, env_path: DEFAULT_ENV_PATH)
        @days = days
        @env_path = env_path
      end

      def run
        connect_django!
        rows = fetch_django_photographers
        puts "[reconcile] fetched #{rows.size} Django registrations from last #{@days} days"

        classified = rows.map { |row| classify(row) }
        path = write_csv(classified)
        print_summary(classified, path)
      ensure
        disconnect_django
      end

      private

      # ----- Django connection -------------------------------------------------

      def connect_django!
        url = parse_database_url
        raise "DATABASE_URL not found in #{@env_path}" if url.blank?

        django_application_record.establish_connection(url: url, name: DJANGO_CONNECTION_NAME)
        # Force connection so we fail fast if DB is unreachable.
        django_application_record.connection.execute('SELECT 1')
      end

      def disconnect_django
        django_application_record.connection_pool&.disconnect!
      rescue StandardError
        # best-effort cleanup
      end

      def parse_database_url
        return nil unless File.exist?(@env_path)

        File.foreach(@env_path, chomp: true) do |line|
          if (m = line.match(/\ADATABASE_URL=(.+)\z/))
            return m[1].strip.delete_prefix('"').delete_suffix('"')
          end
        end
        nil
      end

      def django_application_record
        @django_application_record ||= Class.new(ActiveRecord::Base) do
          self.abstract_class = true
        end.tap do |klass|
          self.class.const_set(:DjangoBase, klass) unless self.class.const_defined?(:DjangoBase)
        end
      end

      def django_photographer_model
        @django_photographer_model ||= begin
          base = django_application_record
          Class.new(base) do
            self.table_name = 'photographers_photographer'
          end
        end
      end

      # ----- Fetch Django rows -------------------------------------------------

      def fetch_django_photographers
        sql = <<~SQL.squish
          SELECT p.id        AS django_id,
                 u.email     AS email,
                 p.handle    AS handle,
                 p.website_url,
                 p.full_name,
                 p.partner_status,
                 p.created_at
          FROM photographers_photographer p
          JOIN authentication_user u ON u.id = p.user_id
          WHERE p.created_at >= NOW() - INTERVAL '#{@days.to_i} days'
            AND p.partner_status IN (#{REGISTERED_STATUSES.join(',')})
          ORDER BY p.created_at DESC
        SQL

        django_application_record.connection.exec_query(sql).to_a
      end

      # ----- Matching ----------------------------------------------------------

      def classify(row)
        candidates = find_directory_candidates(row)
        unique_ids = candidates.map { |c| c[:directory].id }.uniq

        record = base_record(row)
        record[:match_level] = candidates.first&.dig(:level) || 'none'

        if candidates.empty?
          record[:bucket] = 'DIRECTORY_MISSING'
          return record
        end

        if unique_ids.size > 1
          first = candidates.first[:directory]
          record.merge!(directory_fields(first))
          record[:bucket] = 'AMBIGUOUS'
          record[:notes] = "matched directory ids: #{unique_ids.join(',')}"
          return record
        end

        directory = candidates.first[:directory]
        level = candidates.first[:level]
        record.merge!(directory_fields(directory))

        profile = find_profile(directory.id)
        record[:profile_id] = profile&.id
        record[:profile_status] = profile&.partnership_status

        record[:bucket] =
          if profile.nil?
            'PROFILE_MISSING_DIRECTORY_OK'
          elsif profile.signed_up?
            'OK_SIGNED_UP'
          else
            'PROFILE_WRONG_STATUS'
          end

        # Email mismatch is informational — only override when match did
        # NOT come through email and the directory email differs.
        if level != 'L1' && email_mismatch?(row['email'], directory.email)
          record[:notes] = "matched via #{level}; directory email='#{directory.email}' differs from django email='#{row['email']}'"
          record[:bucket] = 'EMAIL_MISMATCH' if record[:bucket] != 'OK_SIGNED_UP'
        end

        record
      end

      def find_directory_candidates(row)
        candidates = []
        seen = Set.new

        email = row['email'].to_s.downcase.strip
        if email.present?
          ::PhotographerDirectory::Photographer.where('LOWER(email) = ?', email).each do |d|
            next if seen.include?(d.id)

            seen << d.id
            candidates << { directory: d, level: 'L1' }
          end
        end

        host = normalize_host(row['website_url'])
        if host.present?
          ::PhotographerDirectory::Photographer
            .where('LOWER(website) IN (?)', [host, "www.#{host}"]).each do |d|
            next if seen.include?(d.id)

            seen << d.id
            candidates << { directory: d, level: 'L2' }
          end
        end

        handle = row['handle'].to_s.downcase.strip
        if handle.present?
          ::PhotographerDirectory::Photographer.where('LOWER(slug) = ?', handle).each do |d|
            next if seen.include?(d.id)

            seen << d.id
            candidates << { directory: d, level: 'L3' }
          end
        end

        candidates
      end

      def normalize_host(url)
        return nil if url.blank?

        raw = url.to_s.strip
        raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
        URI.parse(raw).host&.downcase&.sub(/\Awww\./, '')
      rescue URI::InvalidURIError
        nil
      end

      def email_mismatch?(django_email, directory_email)
        return false if directory_email.blank?
        return false if django_email.blank?

        django_email.to_s.downcase != directory_email.to_s.downcase
      end

      def find_profile(directory_id)
        # NB: external_id is a string in profiles; directory id is bigint.
        ::PhotographerPartnerProfile.find_by(external_id: directory_id.to_s)
      end

      # ----- Output ------------------------------------------------------------

      def base_record(row)
        {
          django_id: row['django_id'],
          email: row['email'],
          handle: row['handle'],
          website_url: row['website_url'],
          full_name: row['full_name'],
          partner_status: PARTNER_STATUS_LABELS.fetch(row['partner_status'], row['partner_status']),
          created_at: row['created_at'],
          match_level: nil,
          directory_id: nil,
          directory_email: nil,
          directory_website: nil,
          directory_slug: nil,
          profile_id: nil,
          profile_status: nil,
          bucket: nil,
          notes: nil
        }
      end

      def directory_fields(directory)
        {
          directory_id: directory.id,
          directory_email: directory.email,
          directory_website: directory.website,
          directory_slug: directory.slug
        }
      end

      def write_csv(classified)
        FileUtils.mkdir_p(Rails.root.join('tmp'))
        path = Rails.root.join('tmp', "outreach_reconciliation_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.csv")
        CSV.open(path, 'w') do |csv|
          headers = classified.first&.keys || base_record({}).keys
          csv << headers
          classified.each { |rec| csv << headers.map { |h| rec[h] } }
        end
        path
      end

      def print_summary(classified, path)
        puts "\n[reconcile] CSV: #{path}"
        puts "[reconcile] total rows: #{classified.size}"
        BUCKETS.each do |bucket|
          count = classified.count { |r| r[:bucket] == bucket }
          puts format('  %-30s %4d', bucket, count)
        end
        leftover = classified.reject { |r| BUCKETS.include?(r[:bucket]) }
        puts format('  %-30s %4d', 'UNCLASSIFIED', leftover.size) if leftover.any?
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
