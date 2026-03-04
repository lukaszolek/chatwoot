class Api::V1::Accounts::InfluencerHashtagsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 50

  def index
    hashtags = filtered_scope
    hashtags = apply_sort(hashtags)
    page = (params[:page] || 1).to_i
    total = hashtags.count
    records = hashtags.offset((page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE)

    render json: {
      data: records.as_json,
      meta: { total: total, page: page, per_page: RESULTS_PER_PAGE, missing_stats_count: missing_stats_count }
    }
  end

  def toggle_star
    hashtag = current_account.influencer_hashtags.find(params[:id])
    hashtag.update!(starred: !hashtag.starred)
    render json: hashtag.as_json
  end

  def fetch_stats
    hashtag = current_account.influencer_hashtags.find(params[:id])
    Influencers::ApifyHashtagStatsJob.perform_later(hashtag.id)
    render json: { message: 'Stats fetch queued' }
  end

  def bulk_fetch_stats
    ids = params[:ids]
    return head :unprocessable_entity if ids.blank?

    hashtags = current_account.influencer_hashtags.where(id: ids)
    hashtags.each { |h| Influencers::ApifyHashtagStatsJob.perform_later(h.id) }
    render json: { message: "Stats fetch queued for #{hashtags.count} hashtags" }
  end

  def fetch_all_missing_stats
    hashtags = current_account.influencer_hashtags.where(stats_fetched_at: nil)
    hashtags = hashtags.by_language(params[:language]) if params[:language].present?
    count = hashtags.count
    hashtags.find_each { |h| Influencers::ApifyHashtagStatsJob.perform_later(h.id) }
    render json: { message: "Stats fetch queued for #{count} hashtags", count: count }
  end

  def starred_for_language
    return head :unprocessable_entity if params[:language].blank?

    hashtags = current_account.influencer_hashtags.starred.by_language(params[:language]).order(profiles_count: :desc)
    render json: hashtags.as_json
  end

  private

  def filtered_scope
    hashtags = current_account.influencer_hashtags
    hashtags = hashtags.by_language(params[:language]) if params[:language].present?
    hashtags = hashtags.starred if params[:starred] == 'true'
    hashtags = hashtags.where('posts_count >= ?', params[:min_posts].to_i) if params[:min_posts].present?
    hashtags = hashtags.where(stats_fetched_at: nil) if params[:missing_stats] == 'true'
    hashtags
  end

  def missing_stats_count
    scope = current_account.influencer_hashtags.where(stats_fetched_at: nil)
    scope = scope.by_language(params[:language]) if params[:language].present?
    scope.count
  end

  def apply_sort(scope)
    allowed = %w[tag profiles_count posts_count starred stats_fetched_at created_at]
    if allowed.include?(params[:sort])
      sort_dir = params[:direction] == 'asc' ? :asc : :desc
      return scope.order(params[:sort] => sort_dir)
    end

    scope.order(Arel.sql('posts_count DESC NULLS LAST, profiles_count DESC'))
  end
end
