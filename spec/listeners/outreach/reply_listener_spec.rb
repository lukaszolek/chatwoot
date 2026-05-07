# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::ReplyListener do
  let(:listener) { described_class.instance }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account, inbox: inbox) }
  let(:profile) do
    PhotographerPartnerProfile.create!(
      account: account,
      external_id: 'reply-listener-profile',
      partnership_status: :imported
    )
  end
  let(:contact) { create(:contact, account: account, email: 'photographer@example.com') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          additional_attributes: { 'campaign_participant_id' => participant.id })
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile,
           current_stage_key: 'reminder_wait', next_action_at: 1.hour.from_now)
  end

  def fire_event(message)
    event = Events::Base.new('message.created', Time.current.to_i, message: message)
    listener.message_created(event)
  end

  describe '#message_created' do
    it 'moves the linked participant into reply_router and marks due' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                 message_type: :incoming, content: 'Yes, interested!')

      freeze_time do
        fire_event(message)
        participant.reload

        expect(participant.current_stage_key).to eq('reply_router')
        expect(participant.next_action_at).to eq(Time.current)
        expect(participant.last_inbound_at).to eq(Time.current)
      end
    end

    it 'is a no-op for outgoing messages' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                 message_type: :outgoing, content: 'Hi')
      original_stage = participant.current_stage_key

      fire_event(message)
      expect(participant.reload.current_stage_key).to eq(original_stage)
    end

    it 'is a no-op for private notes even when message_type=outgoing' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                 message_type: :outgoing, private: true, content: 'internal note')
      original_stage = participant.current_stage_key

      fire_event(message)
      expect(participant.reload.current_stage_key).to eq(original_stage)
    end

    it 'is a no-op when the conversation has no participant link' do
      other_conv = create(:conversation, account: account, inbox: inbox, contact: contact)
      message = create(:message, conversation: other_conv, account: account, inbox: inbox,
                                 message_type: :incoming, content: 'hi')
      expect { fire_event(message) }.not_to raise_error
      expect(participant.reload.current_stage_key).to eq('reminder_wait')
    end

    it 'is a no-op for paused participants' do
      participant.update!(paused: true)
      message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                 message_type: :incoming, content: 'Too late')
      original_stage = participant.current_stage_key

      fire_event(message)
      expect(participant.reload.current_stage_key).to eq(original_stage)
    end

    it 'pauses campaign and marks profile do_not_contact for STOP opt-out' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                 message_type: :incoming, content: 'STOP')

      expect(Outreach::PhotographerDirectory::PropagateConsentJob).to receive(:perform_later)

      fire_event(message)

      expect(participant.reload).to be_paused
      expect(participant.metadata['paused_reason']).to eq('opt_out')
      expect(profile.reload).to be_do_not_contact
      expect(profile).to be_consent_declined
    end
  end
end
