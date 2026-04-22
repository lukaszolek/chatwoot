# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::SendEmailJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account, inbox: inbox) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:contact) { create(:contact, account: account, email: profile.email) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:participant) do
    create(:campaign_participant, outbound_campaign: campaign, account: account,
                                  participatable: profile, contact: contact, conversation: conversation,
                                  current_stage_key: 'reminder_wait')
  end

  describe '#perform' do
    it 'creates an outgoing message and updates last_outbound_at' do
      expect do
        described_class.new.perform(
          participant_id: participant.id,
          conversation_id: conversation.id,
          subject: 'Hi',
          body: 'Body',
          template_slot: 'intro',
          locale: 'en'
        )
      end.to change { conversation.reload.messages.count }.by(1)

      message = conversation.messages.last
      expect(message.content).to eq('Body')
      expect(message.message_type).to eq('outgoing')
      expect(message.additional_attributes.dig('outreach', 'template_slot')).to eq('intro')
      expect(participant.reload.last_outbound_at).to be_present
    end

    it 'no-ops when participant has been destroyed' do
      participant_id = participant.id
      participant.destroy!

      expect do
        described_class.new.perform(
          participant_id: participant_id, conversation_id: conversation.id,
          subject: 'x', body: 'y', template_slot: 'intro', locale: 'en'
        )
      end.not_to(change { conversation.reload.messages.count })
    end
  end
end
