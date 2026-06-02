# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LlmFormatter::PhotographerPartnerLlmFormatter do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, account: account, inbox: inbox, config: { 'default_locale' => 'en' }) }
  let(:profile) do
    create(:photographer_partner_profile, account: account,
                                          owner_name: 'Alex Example',
                                          business_name: 'Studio Alex',
                                          website: 'https://alex.photo',
                                          country_code: 'PL',
                                          instagram_handle: 'alex',
                                          preferred_language: 'pl')
  end
  let(:contact) { create(:contact, account: account, email: profile.email) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:participant) do
    create(:campaign_participant, outbound_campaign: campaign, account: account,
                                  participatable: profile, conversation: conversation, contact: contact)
  end

  it 'formats profile + reply + history' do
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, content: 'Hi Alex, our offer…',
                     additional_attributes: { 'outreach' => { 'subject' => 'Framky partner' } })
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: 'Tak, chętnie!')

    out = described_class.new(participant).format

    expect(out[:profile]).to include('Alex Example', 'Studio Alex', 'PL', 'IG @alex')
    expect(out[:reply_text]).to eq('Tak, chętnie!')
    expect(out[:last_intro_summary]).to include('Framky partner').and include('Hi Alex')
    expect(out[:conversation_history]).to include(match(/^OUT:/), match(/^IN:/))
    expect(out[:locale]).to eq('pl')
  end

  it 'strips quoted history from the latest inbound reply' do
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming,
                     content: "Dzień dobry, potencjalnie mógłbym być zainteresowany współpracą\n\nW dniu 21 maja Łukasz napisał:\nJestem poza biurem")

    out = described_class.new(participant).format

    expect(out[:reply_text]).to eq('Dzień dobry, potencjalnie mógłbym być zainteresowany współpracą')
    expect(out[:conversation_history].last).to eq('IN: Dzień dobry, potencjalnie mógłbym być zainteresowany współpracą')
  end

  it 'returns empty history when no conversation is linked' do
    participant.update!(conversation: nil)

    out = described_class.new(participant).format
    expect(out[:conversation_history]).to eq([])
    expect(out[:reply_text]).to be_nil
    expect(out[:last_intro_summary]).to be_nil
  end
end
