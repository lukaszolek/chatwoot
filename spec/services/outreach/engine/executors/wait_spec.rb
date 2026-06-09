# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::Wait do
  let(:account) { create(:account) }
  let(:campaign) do
    create(:outbound_campaign,
           account: account,
           program_key: 'photographer_partnership')
  end
  let(:profile) do
    PhotographerPartnerProfile.create!(
      account: account,
      external_id: "profile-#{SecureRandom.hex(4)}",
      partnership_status: :imported
    )
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           participatable: profile,
           current_stage_key: 'reminder_wait',
           metadata: { 'locale' => 'pl' })
  end

  describe '#call' do
    context 'with next_stage_key present' do
      let(:stage) do
        create(:campaign_pipeline_stage,
               outbound_campaign: campaign,
               key: 'reminder_send',
               on_enter_action: :send_template,
               template_slot: 'reminder',
               position: 3)
        stage = create(:campaign_pipeline_stage,
                       outbound_campaign: campaign,
                       key: 'reminder_wait',
                       on_enter_action: :wait,
                       auto_advance_after_hours: 120,
                       position: 2)
        stage.update!(next_stage_key: 'reminder_send')
        stage
      end

      it 'parks the participant with next_action_at=stage_entered_at+hours when window still open' do
        participant.update!(stage_entered_at: Time.current)

        described_class.new(participant: participant, stage: stage).call
        participant.reload

        expect(participant.current_stage_key).to eq('reminder_wait')
        expect(participant.next_action_at).to be_within(5.seconds).of(120.hours.from_now)
        expect(participant.paused).to be(false)
      end

      it 'transitions to next_stage_key once the window has elapsed' do
        participant.update!(stage_entered_at: 121.hours.ago)

        described_class.new(participant: participant, stage: stage).call
        participant.reload

        expect(participant.current_stage_key).to eq('reminder_send')
      end

      context 'when the next follow-up locale is disabled' do
        it 'pauses instead of advancing into reminder_send' do
          participant.update!(
            stage_entered_at: 121.hours.ago,
            metadata: { 'locale' => 'nl' }
          )

          described_class.new(participant: participant, stage: stage).call
          participant.reload

          expect(participant.current_stage_key).to eq('reminder_wait')
          expect(participant.paused).to be(true)
          expect(participant.next_action_at).to be_nil
          expect(participant.metadata['paused_reason']).to eq('followup_disabled_for_locale:nl')
        end
      end
    end

    context 'without next_stage_key' do
      let(:stage) do
        create(:campaign_pipeline_stage,
               outbound_campaign: campaign,
               key: 'reminder_wait',
               on_enter_action: :wait,
               position: 2)
      end

      it 'pauses the participant terminally with a reason' do
        described_class.new(participant: participant, stage: stage).call
        participant.reload

        expect(participant.paused).to be(true)
        expect(participant.metadata['paused_reason']).to include('wait_without_next_stage')
      end
    end
  end
end
