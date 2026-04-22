# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Outreach::PartnershipSignupsController, type: :request do
  let(:secret) { 'webhook-secret-test' }
  let(:account) { create(:account) }
  let!(:profile) { create(:photographer_partner_profile, account: account, email: 'alex@example.com', external_id: 'ext-99') }

  def post_signup(payload_hash, signature: nil)
    raw = payload_hash.to_json
    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw)
    post '/webhooks/outreach/partnership_signup',
         params: raw,
         headers: {
           'CONTENT_TYPE' => 'application/json',
           'X-Framky-Signature' => signature || expected
         }
  end

  it 'returns 200 and records signup with a valid signature' do
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => secret) do
      post_signup({
                    email: profile.email, external_id: profile.external_id,
                    handle: 'alexstudio', signed_up_at: Time.current.iso8601
                  })
      expect(response).to have_http_status(:ok)
      expect(profile.reload.partnership_status).to eq('signed_up')
    end
  end

  it 'returns 401 when the signature is missing' do
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => secret) do
      post '/webhooks/outreach/partnership_signup',
           params: { email: profile.email }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'returns 401 when the signature does not match the body' do
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => secret) do
      post_signup({ email: profile.email }, signature: 'bogus')
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'returns 401 when the shared secret is not configured' do
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => nil) do
      post_signup({ email: profile.email })
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'returns 404 when the profile cannot be resolved' do
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => secret) do
      post_signup({ email: 'nobody@nowhere.test', external_id: 'missing' })
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'returns 400 for non-JSON body' do
    raw = 'not json'
    with_modified_env('OUTREACH_PARTNERSHIP_WEBHOOK_SECRET' => secret) do
      post '/webhooks/outreach/partnership_signup',
           params: raw,
           headers: {
             'CONTENT_TYPE' => 'application/json',
             'X-Framky-Signature' => OpenSSL::HMAC.hexdigest('SHA256', secret, raw)
           }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
