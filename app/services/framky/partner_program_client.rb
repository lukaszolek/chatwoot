# Thin HTTParty wrapper over the Framky backend's partner-program REST
# API. Reads FRAMKY_API_URL + FRAMKY_API_TOKEN — same env vars as
# Influencers::CreateVoucherService so we don't fork credentials.
#
# Endpoints listed below are TBD on the backend side. Until they exist,
# the methods return { error: 'not_implemented_yet', ... } so the agent
# can gracefully relay "I'll have a teammate check this manually" without
# crashing the conversation.
class Framky::PartnerProgramClient
  API_URL = ENV.fetch('FRAMKY_API_URL', 'https://api.framky.com')

  class ApiError < StandardError; end

  def registration_status(external_id)
    return { error: 'not_implemented_yet', endpoint: 'GET /v1/partner_program/registrations/by_external_id/:id' } unless feature_enabled?

    request(:get, "/v1/partner_program/registrations/by_external_id/#{CGI.escape(external_id.to_s)}")
  end

  def commission_balance(external_id)
    return { error: 'not_implemented_yet', endpoint: 'GET /v1/partner_program/photographers/:id/balance' } unless feature_enabled?

    request(:get, "/v1/partner_program/photographers/#{CGI.escape(external_id.to_s)}/balance")
  end

  def submit_invoice(external_id, payload)
    return { error: 'not_implemented_yet', endpoint: 'POST /v1/partner_program/invoices' } unless feature_enabled?

    request(:post, '/v1/partner_program/invoices',
            body: payload.merge(photographer_external_id: external_id))
  end

  private

  def feature_enabled?
    ENV.fetch('FRAMKY_PARTNER_PROGRAM_API_ENABLED', 'false') == 'true'
  end

  def request(method, path, body: nil)
    response = HTTParty.send(method,
                             "#{API_URL}#{path}",
                             headers: auth_headers,
                             body: body&.to_json)
    return response.parsed_response if response.success?

    { error: 'api_error', status: response.code, body: response.parsed_response }
  end

  def auth_headers
    {
      'Authorization' => "Token #{ENV.fetch('FRAMKY_API_TOKEN', '')}",
      'Content-Type' => 'application/json'
    }
  end
end
