# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::UnsubscribesController, type: :request do
  let(:secret) { 'unsubscribe-endpoint-secret' }
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile,
           current_stage_key: 'reminder_wait')
  end

  def token_for(target = participant)
    Outreach::UnsubscribeToken.sign(participant_id: target.id, campaign_id: target.outbound_campaign_id)
  end

  around do |example|
    with_modified_env('OUTREACH_UNSUBSCRIBE_SECRET' => secret) { example.run }
  end

  describe 'GET /unsubscribe/:token' do
    it 'renders confirmation and flips the profile to do_not_contact' do
      get "/unsubscribe/#{token_for}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('unsubscribed')
      expect(profile.reload.partnership_status).to eq('do_not_contact')
      expect(participant.reload.paused).to be(true)
    end

    it 'enqueues PropagateConsentJob for directory sync' do
      expect { get "/unsubscribe/#{token_for}" }
        .to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)
        .with(profile.id, 'opt_out', reason: 'list_unsubscribe')
    end

    it 'returns 404 for a tampered/expired token' do
      get '/unsubscribe/not-a-real-token'
      expect(response).to have_http_status(:not_found)
    end

    it 'pauses all participants for the profile (multi-campaign opt-out)' do
      other_campaign = create(:outbound_campaign, :active, account: account)
      other = create(:campaign_participant, outbound_campaign: other_campaign, account: account,
                                            participatable: profile, current_stage_key: 'intro')

      get "/unsubscribe/#{token_for}"
      expect(other.reload.paused).to be(true)
    end
  end

  describe 'POST /unsubscribe/:token (RFC 8058 one-click)' do
    it 'returns 200 and applies the opt-out' do
      post "/unsubscribe/#{token_for}", params: 'List-Unsubscribe=One-Click',
                                        headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
      expect(response).to have_http_status(:ok)
      expect(profile.reload.partnership_status).to eq('do_not_contact')
    end

    it 'returns 404 on bad token' do
      post '/unsubscribe/bogus'
      expect(response).to have_http_status(:not_found)
    end
  end
end
