# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::Terminal do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:stage) do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'terminal',
           on_enter_action: :terminal,
           position: 10)
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           current_stage_key: 'terminal')
  end

  it 'pauses the participant with a reason containing the stage key' do
    described_class.new(participant: participant, stage: stage).call
    participant.reload

    expect(participant.paused).to be(true)
    expect(participant.metadata['paused_reason']).to eq('terminal:terminal')
  end
end
