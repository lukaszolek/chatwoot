# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::SendTemplate do
  let(:account) { create(:account) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           participatable: profile,
           current_stage_key: 'intro')
  end
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) do
    create(:outbound_campaign,
           account: account,
           inbox: inbox,
           config: { 'default_locale' => 'en' })
  end
  let(:profile) do
    create(:photographer_partner_profile,
           account: account,
           email: 'alex@studio-alex.test',
           owner_name: 'Alex Example',
           preferred_language: 'de')
  end

  let(:intro_stage) do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'intro',
           on_enter_action: :send_template,
           template_slot: 'intro',
           position: 1)
  end

  before do
    create(:campaign_template, outbound_campaign: campaign,
                               slot: 'intro', locale: 'de',
                               subject: 'Hallo {{first_name}}',
                               body: 'Body DE {{first_name}}', active: true)
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'reminder_wait', on_enter_action: :wait,
                                     position: 2)
    intro_stage.update!(next_stage_key: 'reminder_wait')
  end

  describe '#call' do
    it 'enqueues SendEmailJob with rendered template and advances stage' do
      expect do
        described_class.new(participant: participant, stage: intro_stage).call
      end.to have_enqueued_job(Outreach::SendEmailJob).with(
        hash_including(
          participant_id: participant.id,
          subject: 'Hallo Alex',
          body: 'Body DE Alex',
          template_slot: 'intro',
          locale: 'de'
        )
      )

      participant.reload
      expect(participant.current_stage_key).to eq('reminder_wait')
      expect(participant.conversation_id).to be_present
      expect(participant.contact_id).to be_present
      expect(participant.last_outbound_at).to be_present
    end

    context 'when no template exists for the participant locale' do
      let(:profile) do
        create(:photographer_partner_profile,
               account: account,
               preferred_language: 'pl')
      end

      it 'falls back to the campaign default_locale when a default template exists' do
        create(:campaign_template,
               outbound_campaign: campaign,
               slot: 'intro',
               locale: 'en',
               subject: 'Hello {{first_name}}',
               body: 'Body EN')

        expect do
          described_class.new(participant: participant, stage: intro_stage).call
        end.to have_enqueued_job(Outreach::SendEmailJob).with(
          hash_including(subject: /Hello/, locale: 'en')
        )
      end

      it 'pauses the participant when no fallback exists either' do
        # no en template; participant locale pl has none either.
        described_class.new(participant: participant, stage: intro_stage).call

        expect(participant.reload.paused).to be(true)
        expect(participant.metadata['paused_reason']).to include('no_template_for_slot:intro')
      end
    end

    context 'with no inbox on the campaign' do
      let(:campaign) do
        create(:outbound_campaign,
               account: account,
               inbox: nil,
               config: { 'default_locale' => 'en' })
      end

      it 'bubbles the InboxMissing error to the runner' do
        expect do
          described_class.new(participant: participant, stage: intro_stage).call
        end.to raise_error(Outreach::Engine::ConversationResolver::InboxMissing)
      end
    end
  end
end
