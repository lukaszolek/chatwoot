# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::SendEmailJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account, inbox: inbox) }
  let(:profile) do
    PhotographerPartnerProfile.create!(
      account: account,
      external_id: "profile-#{SecureRandom.hex(4)}",
      partnership_status: :imported
    )
  end
  let(:contact) { create(:contact, account: account, email: 'alex@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:participant) do
    create(:campaign_participant, outbound_campaign: campaign, account: account,
                                  participatable: profile, contact: contact, conversation: conversation,
                                  current_stage_key: 'reminder_wait')
  end

  let(:secret) { "send-email-secret-#{SecureRandom.hex(4)}" }

  before { flush_outreach_rate_limit_keys }

  def perform!
    described_class.new.perform(
      participant_id: participant.id,
      conversation_id: conversation.id,
      subject: 'Hi',
      body: 'Body',
      template_slot: 'intro',
      locale: 'en'
    )
  end

  describe '#perform' do
    it 'creates an outgoing message with raw body (no unsubscribe footer) + outreach metadata' do
      expect { perform! }.to change { conversation.reload.messages.count }.by(1)

      message = conversation.messages.last
      expect(message.content).to eq('Body')
      expect(message.content).not_to include('unsubscribe')
      expect(message.additional_attributes.dig('outreach', 'template_slot')).to eq('intro')
      expect(message.additional_attributes.dig('outreach', 'subject')).to eq('Hi')
      expect(participant.reload.last_outbound_at).to be_present
    end

    it 'sets conversation.additional_attributes.mail_subject so chatwoot mailer uses the outreach subject' do
      perform!
      expect(conversation.reload.additional_attributes['mail_subject']).to eq('Hi')
    end

    it 'reschedules itself when the recipient-domain rate limit is exhausted' do
      with_modified_env('OUTREACH_MAX_PER_DOMAIN_PER_HOUR' => '0') do
        expect { perform! }
          .to have_enqueued_job(described_class)
          .with(hash_including(participant_id: participant.id))
          .and(not_change { conversation.reload.messages.count })
      end
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

    context 'when intro locale is not enabled for follow-ups' do
      let(:campaign) do
        create(:outbound_campaign, :active,
               account: account,
               inbox: inbox,
               program_key: 'photographer_partnership')
      end

      before do
        create(:campaign_pipeline_stage,
               outbound_campaign: campaign,
               key: 'reminder_send',
               on_enter_action: :send_template,
               template_slot: 'reminder',
               position: 3)
        create(:campaign_pipeline_stage,
               outbound_campaign: campaign,
               key: 'reminder_wait',
               on_enter_action: :wait,
               next_stage_key: 'reminder_send',
               position: 2)
        create(:campaign_pipeline_stage,
               outbound_campaign: campaign,
               key: 'intro',
               on_enter_action: :send_template,
               template_slot: 'intro',
               next_stage_key: 'reminder_wait',
               position: 1)
        participant.update!(current_stage_key: 'intro')
      end

      it 'does not advance into reminder_wait' do
        described_class.new.perform(
          participant_id: participant.id,
          conversation_id: conversation.id,
          subject: 'Hallo',
          body: 'Body',
          template_slot: 'intro',
          locale: 'nl'
        )

        participant.reload
        expect(participant.current_stage_key).to eq('intro')
        expect(participant.paused).to be(true)
        expect(participant.next_action_at).to be_nil
        expect(participant.last_outbound_at).to be_present
        expect(participant.metadata['paused_reason']).to eq('followup_disabled_for_locale:nl')
      end
    end
  end

  def flush_outreach_rate_limit_keys
    Redis::Alfred.scan_each(match: "#{Outreach::RateLimiter::KEY_PREFIX}:*") { |k| Redis::Alfred.delete(k) }
  end
end
