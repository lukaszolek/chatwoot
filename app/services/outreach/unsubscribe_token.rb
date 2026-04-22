# HMAC-signed unsubscribe tokens — stateless, no lookup table.
#
# Token structure: base64url("#{participant_id}:#{campaign_id}:#{issued_at}:#{signature}")
#   signature = HMAC-SHA256(secret, "#{participant_id}:#{campaign_id}:#{issued_at}")
#
# The shared secret is OUTREACH_UNSUBSCRIBE_SECRET. Verification uses a
# constant-time comparison so signature oracles cannot leak via timing.
#
# Tokens are valid for TTL seconds (default 180 days). RFC 8058 assumes
# links may live as long as the hosting inbox — a long TTL matches real
# user behaviour.
#
# Token format is URL-safe by construction (base64url on the outer
# payload; internal separator is ":" which base64 escapes through).
class Outreach::UnsubscribeToken
  class InvalidToken < StandardError; end
  class SecretMissing < StandardError; end

  DEFAULT_TTL = (180 * 24 * 60 * 60) # 180 days
  SECRET_ENV = 'OUTREACH_UNSUBSCRIBE_SECRET'.freeze

  def self.sign(participant_id:, campaign_id:, issued_at: Time.current)
    new(secret: fetch_secret!).sign(
      participant_id: participant_id,
      campaign_id: campaign_id,
      issued_at: issued_at
    )
  end

  def self.verify(token, max_age: DEFAULT_TTL)
    new(secret: fetch_secret!).verify(token, max_age: max_age)
  end

  def self.fetch_secret!
    secret = ENV.fetch(SECRET_ENV, nil)
    raise SecretMissing, "#{SECRET_ENV} is not set" if secret.blank?

    secret
  end

  def initialize(secret:)
    @secret = secret
  end

  def sign(participant_id:, campaign_id:, issued_at:)
    payload = "#{participant_id}:#{campaign_id}:#{issued_at.to_i}"
    signature = compute_signature(payload)
    Base64.urlsafe_encode64("#{payload}:#{signature}", padding: false)
  end

  def verify(token, max_age: DEFAULT_TTL)
    raw = Base64.urlsafe_decode64(token.to_s)
    parts = raw.split(':')
    raise InvalidToken, 'malformed token' if parts.size != 4

    participant_id, campaign_id, issued_at_s, signature = parts
    payload = "#{participant_id}:#{campaign_id}:#{issued_at_s}"
    expected = compute_signature(payload)

    raise InvalidToken, 'signature mismatch' unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    issued_at = Time.zone.at(issued_at_s.to_i)
    raise InvalidToken, 'expired' if Time.current - issued_at > max_age

    {
      participant_id: participant_id.to_i,
      campaign_id: campaign_id.to_i,
      issued_at: issued_at
    }
  rescue ArgumentError => e
    raise InvalidToken, "base64 decode failed: #{e.message}"
  end

  private

  def compute_signature(payload)
    OpenSSL::HMAC.hexdigest('SHA256', @secret, payload)
  end
end
