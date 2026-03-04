class Influencers::HashtagExtractor
  COUNTRY_TO_LANGUAGE = {
    'DE' => 'de', 'AT' => 'de', 'CH' => 'de',
    'PL' => 'pl', 'FR' => 'fr', 'BE' => 'fr',
    'NL' => 'nl', 'GB' => 'en', 'US' => 'en',
    'IT' => 'it', 'ES' => 'es', 'DK' => 'da', 'SE' => 'sv'
  }.freeze

  ELIGIBLE_STATUSES = %w[enriched approved].freeze

  def self.extract(profile)
    new(profile).extract
  end

  def self.extract_all(account)
    account.influencer_profiles.where(status: ELIGIBLE_STATUSES).where.not(target_market: [nil, '']).find_each do |profile|
      extract(profile)
    end
  end

  def initialize(profile)
    @profile = profile
    @account_id = profile.account_id
    @language = COUNTRY_TO_LANGUAGE[profile.target_market]
  end

  def extract
    return if @language.blank?
    return unless ELIGIBLE_STATUSES.include?(@profile.status)

    tags = extract_tags
    return if tags.empty?

    upsert_tags(tags)
  end

  private

  def extract_tags
    captions = collect_captions
    captions.flat_map { |c| c.scan(/#(\w+)/i) }.flatten.map(&:downcase).uniq
  end

  def collect_captions
    # Primary source: raw Apify data has all captions
    apify_posts = Array(@profile.apify_data&.dig('latestPosts'))
    captions = apify_posts.filter_map { |p| p['caption'].presence }

    # Fallback: parsed recent_reels/recent_posts
    if captions.empty?
      posts = Array(@profile.recent_reels) + Array(@profile.recent_posts)
      captions = posts.filter_map { |p| (p['caption'] || p[:caption]).presence }
    end

    captions
  end

  def upsert_tags(tags)
    conn = ActiveRecord::Base.connection
    now = Time.current.iso8601(6)
    values = tags.map do |tag|
      "(#{@account_id}, #{conn.quote(tag)}, #{conn.quote(@language)}, 1, false, '#{now}', '#{now}')"
    end

    sql = <<~SQL.squish
      INSERT INTO influencer_hashtags (account_id, tag, language, profiles_count, starred, created_at, updated_at)
      VALUES #{values.join(', ')}
      ON CONFLICT (account_id, tag, language)
      DO UPDATE SET profiles_count = influencer_hashtags.profiles_count + 1, updated_at = EXCLUDED.updated_at
    SQL

    conn.execute(sql)
  end
end
