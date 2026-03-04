class BackfillCaptionsInRecentMedia < ActiveRecord::Migration[7.0]
  def up
    InfluencerProfile.where.not(apify_data: nil).find_each do |profile|
      attrs = Apify::ResponseParser.parse(profile.apify_data)
      next if attrs[:recent_reels].blank? && attrs[:recent_posts].blank?

      profile.update_columns(
        recent_reels: attrs[:recent_reels],
        recent_posts: attrs[:recent_posts]
      )
    end
  end

  def down
    # irreversible — captions are additive, no data lost
  end
end
