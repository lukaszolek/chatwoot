# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::SendEmailJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, account: account, inbox: inbox) }
  let(:profile) { create(:photographer_partner_profile, account: account, email: 'alex@example.com') }
  let(:contact) { create(:contact, account: account, email: profile.email) }
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
    it 'creates an outgoing message with unsubscribe footer + metadata' do
      with_modified_env('OUTREACH_UNSUBSCRIBE_SECRET' => secret, 'FRONTEND_URL' => 'https://crm.framky.test') do
        expect { perform! }.to change { conversation.reload.messages.count }.by(1)
      end

      message = conversation.messages.last
      expect(message.content).to include('Body')
      expect(message.content).to include('unsubscribe')
      expect(message.additional_attributes.dig('outreach', 'unsubscribe_url')).to start_with('https://crm.framky.test/unsubscribe/')
      expect(message.additional_attributes.dig('outreach', 'template_slot')).to eq('intro')
      expect(participant.reload.last_outbound_at).to be_present
    end

    it 'still sends (without a footer) when the unsubscribe secret is missing' do
      with_modified_env('OUTREACH_UNSUBSCRIBE_SECRET' => nil) do
        expect { perform! }.to change { conversation.reload.messages.count }.by(1)
      end

      expect(conversation.messages.last.content).to eq('Body')
      expect(conversation.messages.last.additional_attributes.dig('outreach', 'unsubscribe_url')).to be_nil
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
  end

  def flush_outreach_rate_limit_keys
    Redis::Alfred.scan_each(match: "#{Outreach::RateLimiter::KEY_PREFIX}:*") { |k| Redis::Alfred.delete(k) }
  end
end
