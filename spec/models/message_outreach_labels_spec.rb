# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, account: account, inbox: inbox) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:contact) { create(:contact, account: account, email: profile.email) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      status: :open,
      label_list: ['outreach_replied'],
      additional_attributes: { 'campaign_participant_id' => participant.id }
    )
  end
  let(:participant) do
    create(
      :campaign_participant,
      outbound_campaign: campaign,
      account: account,
      participatable: profile,
      contact: contact
    )
  end

  it 'marks a manual public outgoing agent reply as sent for outreach conversations' do
    create(
      :message,
      conversation: conversation,
      account: account,
      inbox: inbox,
      sender: campaign.sender_user,
      message_type: :outgoing,
      private: false,
      content: 'Dziekuje za odpowiedz, wracam z linkiem.'
    )

    expect(conversation.reload.label_list).to include('outreach_sent')
    expect(conversation.label_list).not_to include('outreach_replied')
    expect(conversation.status).to eq('pending')
  end
end
