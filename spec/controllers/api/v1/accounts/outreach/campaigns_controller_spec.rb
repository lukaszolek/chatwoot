# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Outreach::Campaigns', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:campaign) { create(:outbound_campaign, :active, account: account, program_key: 'photographer_partnership') }

  describe 'GET /api/v1/accounts/:account_id/outreach/campaigns' do
    it 'returns 401 without auth' do
      get "/api/v1/accounts/#{account.id}/outreach/campaigns"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/outreach/campaigns", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists campaigns for admin' do
      get "/api/v1/accounts/#{account.id}/outreach/campaigns", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.first['program_key']).to eq('photographer_partnership')
    end
  end

  describe 'POST /pause and /resume' do
    it 'toggles status' do
      post "/api/v1/accounts/#{account.id}/outreach/campaigns/#{campaign.id}/pause",
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq('paused')

      post "/api/v1/accounts/#{account.id}/outreach/campaigns/#{campaign.id}/resume",
           headers: admin.create_new_auth_token
      expect(campaign.reload.status).to eq('active')
    end
  end
end
