# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::Wait do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           current_stage_key: 'reminder_wait')
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

      it 'transitions to next_stage_key with next_action_at in the present' do
        freeze_time do
          described_class.new(participant: participant, stage: stage).call
          participant.reload

          expect(participant.current_stage_key).to eq('reminder_send')
          expect(participant.next_action_at).to eq(Time.current)
          expect(participant.stage_entered_at).to eq(Time.current)
          expect(participant.paused).to be(false)
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
