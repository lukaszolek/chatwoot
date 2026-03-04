namespace :influencers do
  desc 'Detect and set language for all influencer profiles that have post data'
  task detect_languages: :environment do
    profiles = InfluencerProfile.joins(:contact).where.not(raw_report_data: {}).or(
      InfluencerProfile.joins(:contact).where.not(apify_data: {})
    )

    total = profiles.count
    updated = 0
    skipped = 0
    failed = 0

    puts "Processing #{total} influencer profiles..."

    profiles.find_each.with_index do |profile, index|
      existing_locale = profile.contact.additional_attributes&.dig('locale')
      if existing_locale.present?
        skipped += 1
        next
      end

      language = Influencers::LanguageDetector.detect_and_set(profile)
      if language.present?
        updated += 1
        puts "  [#{index + 1}/#{total}] #{profile.username}: #{language}"
      else
        failed += 1
        puts "  [#{index + 1}/#{total}] #{profile.username}: could not detect"
      end
    rescue StandardError => e
      failed += 1
      puts "  [#{index + 1}/#{total}] #{profile.username}: ERROR - #{e.message}"
    end

    puts "\nDone! Updated: #{updated}, Skipped (already set): #{skipped}, Failed: #{failed}"
  end
end
