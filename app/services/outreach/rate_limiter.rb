# Per-recipient-domain outbound rate limiter backed by Redis.
#
# Simple fixed-window counter: per every 1-hour bucket (UTC) each
# recipient domain gets at most `max_per_hour` sends. Reservations use
# INCR + EXPIRE so the key auto-expires when the window closes — no
# cleanup job needed.
#
# The caller pattern is reserve-or-defer:
#
#   if Outreach::RateLimiter.new(domain).reserve!
#     send_mail
#   else
#     retry_in(10.minutes)
#   end
#
# Deliberately not a leaky-bucket: gmail/yahoo care about volume-per-hour,
# not smoothness. A fixed window matches their policy shape with a
# single atomic command.
class Outreach::RateLimiter
  KEY_PREFIX = 'outreach:ratelimit'.freeze
  DEFAULT_MAX_PER_HOUR = 50
  WINDOW_SECONDS = 3600

  def initialize(domain, max_per_hour: DEFAULT_MAX_PER_HOUR, now: Time.current)
    @domain = domain.to_s.downcase
    @max = max_per_hour.to_i
    @now = now
  end

  # Attempts to reserve a token. Returns true if under the limit (after
  # incrementing), false if over (decrements the rejected reservation
  # back and signals the caller to defer).
  #
  # Sets TTL on first INCR of a window so the key evaporates when the
  # hour rolls over. Best-effort — if Redis is unreachable we fail open
  # (return true + log) rather than block all outbound.
  def reserve!
    return true if @domain.empty?

    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, WINDOW_SECONDS) if count == 1

    if count > @max
      Rails.logger.info("[outreach.rate_limiter] domain=#{@domain} count=#{count} over=#{@max} -> defer")
      decrement(key)
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.error("[outreach.rate_limiter] domain=#{@domain} redis_error=#{e.class.name}: #{e.message}")
    true
  end

  # Release a previously-reserved token (e.g. after a send error bubbles
  # up). Not strictly needed — the window expires anyway — but keeps
  # counts accurate on transient failures.
  def release!
    return if @domain.empty?

    decrement(key)
  rescue StandardError => e
    Rails.logger.error("[outreach.rate_limiter] domain=#{@domain} release_error=#{e.message}")
  end

  def current_count
    Redis::Alfred.get(key).to_i
  end

  def self.domain_from_email(email)
    email.to_s.split('@', 2)[1].to_s.downcase.strip
  end

  private

  def key
    "#{KEY_PREFIX}:#{current_bucket}:#{@domain}"
  end

  def current_bucket
    (@now.to_i / WINDOW_SECONDS).to_s
  end

  def decrement(redis_key)
    $alfred.with { |conn| conn.decr(redis_key) } # rubocop:disable Style/GlobalVars
  end
end
