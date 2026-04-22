# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Attribution::SignupRecorder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account, inbox: inbox) }
  let(:profile) do
    create(:photographer_partner_profile, account: account,
                                          email: 'alex@example.com', external_id: 'ext-42')
  end
  let(:contact) { create(:contact, account: account, email: profile.email) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:participant) do
    create(:campaign_participant, outbound_campaign: campaign, account: account,
                                  participatable: profile, conversation: conversation,
                                  current_stage_key: 'reminder_wait')
  end

  it 'transitions profile, advances participant, posts note, creates attribution event' do
    participant # force creation
    described_class.new(
      'email' => 'alex@example.com', 'external_id' => 'ext-42',
      'handle' => 'alexstudio', 'signed_up_at' => '2026-04-22T12:34:56Z',
      'utm' => { 'participant_id' => participant.id }
    ).call

    expect(profile.reload.partnership_status).to eq('signed_up')
    expect(participant.reload.current_stage_key).to eq('terminal')
    expect(participant.paused).to be(true)
    note = conversation.reload.messages.where(private: true).last
    expect(note.content).to include('Zarejestrowany').and include('alexstudio')
    event = CampaignAttributionEvent.where(campaign_participant: participant).last
    expect(event.event_type).to eq('partnership_signup')
    expect(event.payload['handle']).to eq('alexstudio')
  end

  it 'is idempotent — replay does not duplicate notes or events' do
    participant # force creation
    payload = {
      'email' => 'alex@example.com', 'external_id' => 'ext-42',
      'handle' => 'alexstudio', 'signed_up_at' => '2026-04-22T12:34:56Z',
      'utm' => { 'participant_id' => participant.id }
    }

    described_class.new(payload).call
    expect { described_class.new(payload).call }
      .to not_change(CampaignAttributionEvent, :count)
      .and(not_change { conversation.reload.messages.where(private: true).count })
  end

  it 'resolves profile by email when external_id is absent' do
    participant # force creation
    described_class.new(
      'email' => 'alex@example.com', 'handle' => 'alexstudio'
    ).call

    expect(profile.reload.partnership_status).to eq('signed_up')
  end

  it 'raises ProfileNotFound with a helpful message when profile is missing' do
    expect do
      described_class.new('email' => 'nobody@x.test', 'external_id' => 'nope').call
    end.to raise_error(described_class::ProfileNotFound, /no profile/)
  end
end
