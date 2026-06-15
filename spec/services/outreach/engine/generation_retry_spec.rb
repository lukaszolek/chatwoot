# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::GenerationRetry do
  let(:campaign) { create(:outbound_campaign, :active, :photographer_partnership) }

  describe '.candidate_scope' do
    it 'selects only payment required intro participants for payment_required' do
      payment_required = create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: create(:contact, account: campaign.account),
        metadata: {
          'last_error' => 'executor_error:RubyLLM::PaymentRequiredError:Insufficient credits',
          'last_error_at' => 2.hours.ago.iso8601
        }
      )
      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: create(:contact, account: campaign.account),
        metadata: {
          'last_error' => 'executor_error:RubyLLM::BadRequestError:Provider returned error',
          'last_error_at' => 1.hour.ago.iso8601
        }
      )
      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        current_stage_key: 'reminder_wait',
        participatable: create(:contact, account: campaign.account),
        metadata: {
          'last_error' => 'executor_error:RubyLLM::PaymentRequiredError:Insufficient credits',
          'last_error_at' => 1.hour.ago.iso8601
        }
      )

      ids = described_class.candidate_scope(campaign, error_kind: :payment_required).pluck(:id)

      expect(ids).to contain_exactly(payment_required.id)
    end

    it 'selects only provider error intro participants for provider_error' do
      provider_error = create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: create(:contact, account: campaign.account),
        metadata: {
          'last_error' => 'executor_error:RubyLLM::BadRequestError:Provider returned error',
          'last_error_at' => 2.hours.ago.iso8601
        }
      )
      create(
        :campaign_participant,
        outbound_campaign: campaign,
        account: campaign.account,
        participatable: create(:contact, account: campaign.account),
        metadata: {
          'last_error' => 'executor_error:RubyLLM::PaymentRequiredError:Insufficient credits',
          'last_error_at' => 1.hour.ago.iso8601
        }
      )

      ids = described_class.candidate_scope(campaign, error_kind: :provider_error).pluck(:id)

      expect(ids).to contain_exactly(provider_error.id)
    end
  end

  describe '#call' do
    it 'clears retry-related metadata and keeps unrelated keys' do
      travel_to Time.zone.parse('2026-05-29 12:00:00 UTC') do
        participant = create(
          :campaign_participant,
          outbound_campaign: campaign,
          account: campaign.account,
          participatable: create(:contact, account: campaign.account),
          paused: true,
          next_action_at: 2.hours.from_now,
          metadata: {
            'last_error' => 'executor_error:RubyLLM::PaymentRequiredError:Insufficient credits',
            'last_error_at' => 2.hours.ago.iso8601,
            'processing_started_at' => 1.hour.ago.iso8601,
            'processing_reason' => 'outreach_runner_claim',
            'other_key' => 'keep-me'
          }
        )

        described_class.new(participant).call

        participant.reload
        expect(participant.paused).to be(false)
        expect(participant.metadata['last_error']).to be_nil
        expect(participant.metadata['last_error_at']).to be_nil
        expect(participant.metadata['processing_started_at']).to be_nil
        expect(participant.metadata['processing_reason']).to eq('outreach_runner_claim')
        expect(participant.metadata['other_key']).to eq('keep-me')
      end
    end

    it 'schedules the participant immediately for a retry' do
      travel_to Time.zone.parse('2026-05-29 12:00:00 UTC') do
        participant = create(
          :campaign_participant,
          outbound_campaign: campaign,
          account: campaign.account,
          participatable: create(:contact, account: campaign.account),
          paused: true,
          next_action_at: 2.hours.from_now,
          metadata: {
            'last_error' => 'executor_error:RubyLLM::PaymentRequiredError:Insufficient credits',
            'last_error_at' => 2.hours.ago.iso8601,
            'processing_started_at' => 1.hour.ago.iso8601
          }
        )

        described_class.new(participant).call

        expect(participant.reload.next_action_at).to eq(Time.current)
        expect(participant.metadata['generation_retry_requested_at']).to eq(Time.current.iso8601)
      end
    end

    it 'returns an escalated participant with a rejected intro draft to the intro stage' do
      travel_to Time.zone.parse('2026-05-29 12:00:00 UTC') do
        participant = create(
          :campaign_participant,
          outbound_campaign: campaign,
          account: campaign.account,
          participatable: create(:contact, account: campaign.account),
          current_stage_key: 'escalated',
          paused: true,
          next_action_at: nil
        )
        conversation = create(:conversation, account: campaign.account)
        participant.update!(conversation: conversation)
        create(
          :message,
          account: campaign.account,
          conversation: conversation,
          message_type: 'outgoing',
          private: true,
          additional_attributes: {
            'outreach_draft' => true,
            'draft_status' => 'rejected',
            'template_slot' => 'intro',
            'campaign_participant_id' => participant.id
          }
        )

        described_class.new(participant).call

        participant.reload
        expect(participant.current_stage_key).to eq('intro')
        expect(participant.paused).to be(false)
        expect(participant.next_action_at).to eq(Time.current)
      end
    end
  end
end
