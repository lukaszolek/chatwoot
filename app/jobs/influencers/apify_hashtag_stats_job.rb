class Influencers::ApifyHashtagStatsJob < ApplicationJob
  queue_as :low
  retry_on Apify::Client::ApiError, wait: :polynomially_longer, attempts: 3

  HASHTAG_STATS_ACTOR_ID = 'apify~instagram-hashtag-stats'.freeze

  def perform(hashtag_id)
    hashtag = InfluencerHashtag.find(hashtag_id)
    data = Apify::Client.new.run_actor(HASHTAG_STATS_ACTOR_ID, { hashtags: [hashtag.tag] })
    stats = Array(data).first || {}

    hashtag.update!(
      posts_count: stats['postsCount'],
      apify_stats: stats,
      stats_fetched_at: Time.current
    )
  end
end
