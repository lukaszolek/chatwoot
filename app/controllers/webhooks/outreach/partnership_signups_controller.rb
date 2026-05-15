# Receives signup notifications from framky.com (Django) after a
# photographer completes partnership registration. HMAC-authenticated
# via OUTREACH_PARTNERSHIP_WEBHOOK_SECRET.
#
# Expected body (JSON):
#   {
#     "email": "alex@studio.example",
#     "external_id": "12345",
#     "handle": "alexstudio",
#     "signed_up_at": "2026-04-22T12:34:56Z",
#     "utm": { "participant_id": 42 }
#   }
#
# Expected header:
#   X-Framky-Signature: hex(HMAC-SHA256(secret, raw_body))
#   (optional "sha256=" prefix is accepted for GitHub-style senders)
class Webhooks::Outreach::PartnershipSignupsController < ActionController::API
  SIGNATURE_HEADER = 'X-Framky-Signature'.freeze
  SECRET_ENV = 'OUTREACH_PARTNERSHIP_WEBHOOK_SECRET'.freeze

  def create
    raw_body = request.body.read

    return head :unauthorized unless signature_valid?(raw_body)

    payload = parse_payload!(raw_body)
    return head :bad_request unless payload

    Outreach::Attribution::SignupRecorder.new(payload).call
    head :ok
  rescue Outreach::Attribution::SignupRecorder::ProfileNotFound => e
    Rails.logger.info("[outreach.signup] 404 #{e.message}")
    head :not_found
  rescue StandardError => e
    Rails.logger.error("[outreach.signup] 500 #{e.class}: #{e.message}")
    head :internal_server_error
  end

  private

  def signature_valid?(raw_body)
    secret = ENV.fetch(SECRET_ENV, nil)
    return false if secret.blank?

    provided = request.headers[SIGNATURE_HEADER].to_s.delete_prefix('sha256=')
    return false if provided.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end

  def parse_payload!(raw_body)
    JSON.parse(raw_body)
  rescue JSON::ParserError
    nil
  end
end
