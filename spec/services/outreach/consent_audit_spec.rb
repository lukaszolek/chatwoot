# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::ConsentAudit do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account) }

  def stub_source(profile, marketing_consent:, unsubscribed: false)
    source = double( # rubocop:disable RSpec/VerifiedDoubles
      id: profile.external_id,
      marketing_consent: marketing_consent,
      unsubscribed_from_all_campaigns: unsubscribed
    )
    allow(PhotographerDirectory::Photographer).to receive(:find_by).with(id: profile.external_id).and_return(source)
  end

  it 'heals outbound drift: chatwoot DNC but directory still consenting' do
    profile = create(:photographer_partner_profile, account: account, partnership_status: :do_not_contact)
    create(:campaign_participant, outbound_campaign: campaign, account: account, participatable: profile)
    stub_source(profile, marketing_consent: true, unsubscribed: false)

    expect do
      described_class.run!
    end.to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)
      .with(profile.id, 'opt_out', reason: 'consent_drift_heal')

    event = CampaignAttributionEvent.where(event_type: described_class::DRIFT_EVENT_TYPE).last
    expect(event.payload['direction']).to eq('outbound')
  end

  it 'pauses locally when directory says DNC but chatwoot is still active' do
    profile = create(:photographer_partner_profile, account: account, partnership_status: :contacted)
    participant = create(:campaign_participant, outbound_campaign: campaign, account: account,
                                                participatable: profile, paused: false)
    stub_source(profile, marketing_consent: false, unsubscribed: true)

    described_class.run!

    expect(profile.reload.partnership_status).to eq('do_not_contact')
    expect(participant.reload.paused).to be(true)
  end

  it 'returns a summary hash for metrics' do
    profile = create(:photographer_partner_profile, account: account, partnership_status: :do_not_contact)
    create(:campaign_participant, outbound_campaign: campaign, account: account, participatable: profile)
    stub_source(profile, marketing_consent: true)

    summary = described_class.run!
    expect(summary).to include(:heal_outbound, :pause_local, :errors)
    expect(summary[:heal_outbound]).to eq(1)
  end

  it 'counts errors instead of raising when the directory lookup explodes' do
    profile = create(:photographer_partner_profile, account: account, partnership_status: :do_not_contact)
    create(:campaign_participant, outbound_campaign: campaign, account: account, participatable: profile)
    allow(PhotographerDirectory::Photographer).to receive(:find_by).and_raise(ActiveRecord::ConnectionNotEstablished)

    summary = described_class.run!
    expect(summary[:heal_outbound]).to eq(0)
    expect(summary[:pause_local]).to eq(0)
  end
end
