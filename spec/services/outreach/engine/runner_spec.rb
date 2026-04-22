# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Runner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) do
    create(:outbound_campaign, :active,
           account: account, inbox: inbox,
           config: { 'default_locale' => 'en' })
  end

  let(:intro_stage) do
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'intro', on_enter_action: :send_template,
                                     template_slot: 'intro', position: 1)
  end

  before do
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'reminder_wait', on_enter_action: :wait,
                                     auto_advance_after_hours: 120, position: 2)
    intro_stage.update!(next_stage_key: 'reminder_wait')
    create(:campaign_template, outbound_campaign: campaign, slot: 'intro', locale: 'en',
                               subject: 'Hi', body: 'Body', active: true)
  end

  describe '#tick' do
    it 'returns 0 when campaign is not active' do
      campaign.update!(status: :paused)
      expect(described_class.new(campaign).tick).to eq(0)
    end

    it 'dispatches due participants and skips paused/future ones' do
      profile_due = create(:photographer_partner_profile, account: account)
      profile_paused = create(:photographer_partner_profile, account: account)
      profile_future = create(:photographer_partner_profile, account: account)

      p_due = create(:campaign_participant, outbound_campaign: campaign, account: account,
                                            participatable: profile_due,
                                            current_stage_key: 'intro',
                                            next_action_at: 1.minute.ago)
      create(:campaign_participant, outbound_campaign: campaign, account: account,
                                    participatable: profile_paused,
                                    current_stage_key: 'intro',
                                    next_action_at: 1.minute.ago,
                                    paused: true)
      create(:campaign_participant, outbound_campaign: campaign, account: account,
                                    participatable: profile_future,
                                    current_stage_key: 'intro',
                                    next_action_at: 1.hour.from_now)

      count = described_class.new(campaign).tick

      expect(count).to eq(1)
      expect(p_due.reload.current_stage_key).to eq('reminder_wait')
    end

    it 'backs off the participant by 10 minutes when an executor raises' do
      profile = create(:photographer_partner_profile, account: account)
      participant = create(:campaign_participant,
                           outbound_campaign: campaign, account: account,
                           participatable: profile,
                           current_stage_key: 'intro',
                           next_action_at: 1.minute.ago)

      executor = instance_double(Outreach::Engine::Executors::SendTemplate)
      allow(executor).to receive(:call).and_raise('boom')
      allow(Outreach::Engine::Executors::SendTemplate).to receive(:new).and_return(executor)

      described_class.new(campaign).tick
      participant.reload

      expect(participant.next_action_at).to be_within(5.seconds).of(10.minutes.from_now)
      expect(participant.metadata['last_error']).to include('executor_error')
      expect(participant.current_stage_key).to eq('intro') # rolled back
    end

    it 'backs off and logs when the participant is on an unknown stage key' do
      profile = create(:photographer_partner_profile, account: account)
      participant = create(:campaign_participant,
                           outbound_campaign: campaign, account: account,
                           participatable: profile,
                           current_stage_key: 'ghost_stage',
                           next_action_at: 1.minute.ago)

      described_class.new(campaign).tick
      participant.reload

      expect(participant.metadata['last_error']).to include('missing_stage:ghost_stage')
      expect(participant.next_action_at).to be_within(5.seconds).of(10.minutes.from_now)
    end
  end

  describe 'batch size' do
    it 'honours campaign.config.tick_batch_size' do
      campaign.update!(config: campaign.config.merge('tick_batch_size' => 1))
      profile_a = create(:photographer_partner_profile, account: account)
      profile_b = create(:photographer_partner_profile, account: account)
      create(:campaign_participant, outbound_campaign: campaign, account: account,
                                    participatable: profile_a,
                                    current_stage_key: 'intro',
                                    next_action_at: 1.minute.ago)
      create(:campaign_participant, outbound_campaign: campaign, account: account,
                                    participatable: profile_b,
                                    current_stage_key: 'intro',
                                    next_action_at: 1.minute.ago)

      count = described_class.new(campaign).tick
      expect(count).to eq(1)
    end
  end
end
