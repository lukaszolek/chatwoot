# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Outreach::PhotographerPartnerProfiles', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    3.times { create(:photographer_partner_profile, account: account) }
    # preload_sources! hits the secondary directory DB which does not exist in
    # CI — stub it out so controller actions return 200 instead of 500.
    allow(PhotographerPartnerProfile).to receive(:preload_sources!) { |profiles| profiles }
  end

  describe 'GET #index' do
    it 'returns paginated list with meta for admins' do
      get "/api/v1/accounts/#{account.id}/outreach/photographer_partner_profiles",
          headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['meta']['total']).to eq(3)
      expect(body['data'].size).to eq(3)
    end

    it 'filters by status' do
      PhotographerPartnerProfile.first.update!(partnership_status: :signed_up)
      get "/api/v1/accounts/#{account.id}/outreach/photographer_partner_profiles",
          headers: admin.create_new_auth_token,
          params: { status: 'signed_up' }
      expect(response.parsed_body['meta']['total']).to eq(1)
    end

    it 'filters by search query via the directory search stub' do
      target = PhotographerPartnerProfile.first
      mock_scope = double('photographer_scope') # rubocop:disable RSpec/VerifiedDoubles
      allow(mock_scope).to receive(:pluck).with(:id).and_return([target.external_id])
      allow(Outreach::PhotographerDirectory::SearchFilters).to receive(:apply).and_return(mock_scope)

      get "/api/v1/accounts/#{account.id}/outreach/photographer_partner_profiles",
          headers: admin.create_new_auth_token,
          params: { q: 'Studio' }
      expect(response.parsed_body['meta']['total']).to eq(1)
    end
  end

  describe 'POST /opt_out' do
    it 'flips status to do_not_contact and enqueues PropagateConsentJob' do
      profile = PhotographerPartnerProfile.first

      expect do
        post "/api/v1/accounts/#{account.id}/outreach/photographer_partner_profiles/#{profile.id}/opt_out",
             headers: admin.create_new_auth_token
      end.to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)
        .with(profile.id, 'opt_out', reason: 'operator_manual')

      expect(profile.reload.partnership_status).to eq('do_not_contact')
    end
  end
end
