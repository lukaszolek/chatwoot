# Pulls order counts (total / last 30d / last 90d + first/last completed
# timestamps) from an external Framky orders stats endpoint and caches
# them on PhotographerPartnerProfile. Called by the "Refresh stats"
# button in the kanban UI and by a periodic job.
#
# The external endpoint is expected at:
#   POST  $FRAMKY_ORDER_STATS_URL
#   Authorization: Bearer $FRAMKY_ORDER_STATS_TOKEN
#   Content-Type: application/json
#   { "external_ids": ["...", "..."], "emails": ["...", "..."] }
#
# and responds with:
#   { "photographers": [
#       { "external_id": "...",
#         "email": "...",
#         "orders_total":   N,
#         "orders_last_30d": N,
#         "orders_last_90d": N,
#         "first_order_completed_at": "2024-..." | null,
#         "last_order_completed_at":  "2024-..." | null },
#       ...
#     ] }
#
# Matching prefers external_id, falls back to email. Missing rows are
# treated as "zero orders" — the fetcher still refreshes stats_refreshed_at
# so the UI can show how fresh the data is.
#
# If the URL or token is not configured, the fetcher is a no-op that just
# stamps `order_stats_refreshed_at` so the UI's "Refresh" button still
# feels responsive during local dev.
class Outreach::OrderStats::Fetcher
  Result = Struct.new(:updated, :unchanged, :unmatched, :errors, :skipped, keyword_init: true) do
    def to_h = { updated: updated, unchanged: unchanged, unmatched: unmatched, errors: errors.first(5), skipped: skipped }
  end

  TIMEOUT_SECONDS = 15
  BATCH_SIZE = 200

  def initialize(account:, profile_ids: nil)
    @account = account
    @profile_ids = profile_ids
  end

  def perform
    profiles = scope.to_a
    return empty_result.tap { |r| r.skipped = 'no profiles' } if profiles.empty?

    if endpoint_url.blank? || endpoint_token.blank?
      PhotographerPartnerProfile.where(id: profiles.map(&:id))
                                .update_all(order_stats_refreshed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      return empty_result.tap { |r| r.skipped = 'FRAMKY_ORDER_STATS_URL / _TOKEN not set' }
    end

    result = Result.new(updated: 0, unchanged: 0, unmatched: 0, errors: [], skipped: nil)
    profiles.each_slice(BATCH_SIZE) { |batch| process_batch(batch, result) }
    result
  end

  private

  attr_reader :account

  def scope
    base = account.photographer_partner_profiles
    @profile_ids ? base.where(id: @profile_ids) : base
  end

  def process_batch(batch, result)
    payload = {
      external_ids: batch.map(&:external_id).compact_blank,
      emails: batch.map(&:email).compact_blank
    }
    response = post_json(payload)
    rows = Array(response['photographers'])
    by_ext = rows.index_by { |r| r['external_id'].to_s }
    by_email = rows.index_by { |r| r['email'].to_s.downcase }
    now = Time.current

    batch.each do |profile|
      row = by_ext[profile.external_id.to_s] || by_email[profile.email.to_s.downcase]
      stats = stats_from_row(row)
      changed = apply_stats(profile, stats, now)
      if row.nil?
        result.unmatched += 1
      elsif changed
        result.updated += 1
      else
        result.unchanged += 1
      end
    end
  rescue StandardError => e
    Rails.logger.error("[outreach.order_stats] batch failed: #{e.class}: #{e.message}")
    result.errors << "#{e.class}: #{e.message}"
  end

  def stats_from_row(row)
    return zero_stats if row.nil?

    {
      orders_total: row['orders_total'].to_i,
      orders_last_30d: row['orders_last_30d'].to_i,
      orders_last_90d: row['orders_last_90d'].to_i,
      first_order_completed_at: parse_time(row['first_order_completed_at']),
      last_order_completed_at: parse_time(row['last_order_completed_at'])
    }
  end

  def zero_stats
    { orders_total: 0, orders_last_30d: 0, orders_last_90d: 0,
      first_order_completed_at: nil, last_order_completed_at: nil }
  end

  def apply_stats(profile, stats, now)
    changed = stats.any? { |k, v| profile.send(k) != v }
    profile.update_columns(stats.merge(order_stats_refreshed_at: now)) # rubocop:disable Rails/SkipsModelValidations
    changed
  end

  def post_json(payload)
    uri = URI.parse(endpoint_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = TIMEOUT_SECONDS
    http.open_timeout = TIMEOUT_SECONDS
    req = Net::HTTP::Post.new(uri.request_uri,
                              'Authorization' => "Bearer #{endpoint_token}",
                              'Content-Type' => 'application/json')
    req.body = payload.to_json
    res = http.request(req)
    raise "HTTP #{res.code}: #{res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def endpoint_url = ENV.fetch('FRAMKY_ORDER_STATS_URL', nil)
  def endpoint_token = ENV.fetch('FRAMKY_ORDER_STATS_TOKEN', nil)

  def empty_result
    Result.new(updated: 0, unchanged: 0, unmatched: 0, errors: [], skipped: nil)
  end
end
