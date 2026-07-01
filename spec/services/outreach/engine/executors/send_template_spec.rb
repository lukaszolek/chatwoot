# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::SendTemplate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) do
    create(:outbound_campaign,
           account: account,
           inbox: inbox,
           config: { 'default_locale' => 'en' })
  end
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:contact) { create(:contact, account: account, email: 'alex@studio.test') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           participatable: profile,
           conversation: conversation,
           contact: contact,
           current_stage_key: 'intro')
  end
  let(:intro_stage) do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'intro',
           on_enter_action: :send_template,
           template_slot: 'intro',
           position: 1)
  end
  let(:compose_result) do
    {
      subject: 'Hallo Alex',
      body: 'Guten Tag! Here is our offer.',
      locale: 'de',
      fallback: false,
      model: 'deepseek/test',
      prompt_version: '1',
      input_digest: 'abc123',
      output: {},
      token_usage: {},
      provider_metadata: {},
      latency_ms: 100
    }
  end

  before do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'reminder_wait',
           on_enter_action: :wait,
           position: 2)
    intro_stage.update!(next_stage_key: 'reminder_wait')

    composer = instance_double(Outreach::Llm::MessageComposer::Intro, call: compose_result)
    allow(Outreach::Llm::MessageComposer::Intro).to receive(:new).and_return(composer)
    allow(Outreach::TranslateForAgents).to receive(:call)
  end

  describe '#call' do
    it 'creates a draft and parks the participant when manual_review_mode is on' do
      described_class.new(participant: participant, stage: intro_stage).call

      participant.reload
      expect(participant.next_action_at).to be_nil
      expect(participant.current_stage_key).to eq('intro')
      draft = conversation.messages.find_by(
        "additional_attributes->>'outreach_draft' = 'true'"
      )
      expect(draft).to be_present
    end

    it 'enqueues SendEmailJob and advances stage when manual_review_mode is off' do
      campaign.update!(manual_review_mode: false)

      expect do
        described_class.new(participant: participant, stage: intro_stage).call
      end.to have_enqueued_job(Outreach::SendEmailJob)

      participant.reload
      expect(participant.current_stage_key).to eq('reminder_wait')
    end

    context 'with no inbox on the campaign' do
      let(:campaign) do
        create(:outbound_campaign,
               account: account,
               inbox: nil,
               config: { 'default_locale' => 'en' })
      end
      let(:participant) do
        create(:campaign_participant,
               outbound_campaign: campaign,
               account: account,
               participatable: profile,
               current_stage_key: 'intro')
      end

      it 'bubbles the InboxMissing error to the runner' do
        expect do
          described_class.new(participant: participant, stage: intro_stage).call
        end.to raise_error(Outreach::Engine::ConversationResolver::InboxMissing)
      end
    end
  end
end
