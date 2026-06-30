# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::ClassifyReply do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:profile) { PhotographerPartnerProfile.create!(account: account, external_id: SecureRandom.uuid) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      additional_attributes: {
        'outbound_campaign_program_key' => campaign.program_key,
        'campaign_participant_id' => participant.id
      }
    )
  end
  let(:router_stage) do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'reply_router',
           on_enter_action: :classify_reply,
           position: 6,
           branch_rules: {
             'interested_commission' => { 'target' => 'auto_reply_commission', 'min_confidence' => 0.9 },
             'declined' => { 'target' => 'terminal', 'min_confidence' => 0.85 },
             'spam' => { 'target' => 'terminal', 'min_confidence' => 0.8 }
           })
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile,
           current_stage_key: 'reply_router')
  end

  # These target stages are referenced by branch_rules in the router stage
  # above. They need to exist for next_stage_key / target validation to pass.
  before do
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'terminal', on_enter_action: :terminal, position: 10)
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'escalated', on_enter_action: :escalate_to_user, position: 9)
    create(:campaign_pipeline_stage, outbound_campaign: campaign,
                                     key: 'auto_reply_commission',
                                     on_enter_action: :send_template,
                                     template_slot: 'reply_interested_commission', position: 7)
    allow(profile).to receive(:email).and_return('alain.baroni@ab-photo-france.fr')
  end

  def stub_classifier(**outcome)
    classifier = instance_double(Outreach::Llm::ReplyClassifier, call: outcome)
    allow(Outreach::Llm::ReplyClassifier).to receive(:new).and_return(classifier)
  end

  describe '#call' do
    context 'when confidence >= rule.min_confidence' do
      it 'records decision as auto_send and parks participant (manual_review_mode default)' do
        stub_classifier(
          intent_class: 'interested_commission', confidence: 0.95,
          model: 'stub-1', output: { 'reasoning' => 'clear yes' }
        )

        described_class.new(participant: participant, stage: router_stage).call

        decision = CampaignLlmDecision.last
        expect(decision.routed_to).to eq('auto_send')
        expect(decision.confidence).to be_within(0.001).of(0.95)
        # manual_review_mode defaults to true → participant is parked, not transitioned
        expect(participant.reload.next_action_at).to be_nil
        expect(participant.current_stage_key).to eq('reply_router')
      end
    end

    context 'when a reply comes from a different sender email in the same conversation' do
      it 'still creates an operator draft reply and stores a mismatch warning' do
        participant.update!(conversation: conversation)
        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: create(:contact, account: account, email: 'lain.mars@gmail.com'),
          message_type: :incoming,
          private: false,
          content: 'oui volontiers',
          content_attributes: { email: { 'from' => ['lain.mars@gmail.com'] } }
        )

        stub_classifier(
          intent_class: 'interested_signup',
          confidence: 0.95,
          model: 'stub-1',
          output: { 'reasoning' => 'clear yes' }
        )

        composed = {
          subject: 'Re: Framky',
          body: 'Bonjour Alain, voici le lien.',
          locale: 'fr',
          model: 'deepseek/deepseek-v4-flash',
          prompt_version: 'outreach.compose_reply.v1',
          input_digest: 'abc',
          output: {},
          tool_calls: [],
          token_usage: {},
          provider_metadata: {},
          latency_ms: 10,
          escalate: false
        }
        executor = described_class.new(participant: participant, stage: router_stage)
        allow(executor).to receive(:compose_reply).and_return(composed)

        executor.call

        draft = conversation.messages.outreach_drafts.order(created_at: :desc).first
        expect(draft).to be_present
        expect(draft.additional_attributes['template_slot']).to eq('reply')
        expect(draft.additional_attributes['reply_sender_mismatch']).to be(true)
        expect(draft.additional_attributes['reply_sender_email']).to eq('lain.mars@gmail.com')
        expect(participant.reload.metadata['reply_sender_mismatch']).to be(true)
        expect(participant.metadata['reply_sender_email']).to eq('lain.mars@gmail.com')
      end
    end

    context 'when target is the escalated stage' do
      before do
        router_stage.update!(branch_rules: router_stage.branch_rules.merge(
          'interested_signup' => { 'target' => 'escalated', 'min_confidence' => 0.85 }
        ))
      end

      it 'routes signup intent to operator_draft (composer handles it, not escalate)' do
        stub_classifier(intent_class: 'interested_signup', confidence: 0.9, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        # signup intent at >= MIN_DRAFT_CONFIDENCE → operator_draft (compose reply draft)
        expect(CampaignLlmDecision.last.routed_to).to eq('operator_draft')
        # no conversation → compose_reply_draft! skipped → parked
        expect(participant.reload.next_action_at).to be_nil
      end
    end

    context 'when confidence is below draft floor (< 0.5)' do
      it 'escalates with reason capturing intent class' do
        stub_classifier(intent_class: 'interested_commission', confidence: 0.1, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        expect(participant.reload.current_stage_key).to eq('escalated')
        expect(participant.metadata['escalation_reason']).to eq('classifier_low_confidence:interested_commission')
        expect(CampaignLlmDecision.last.routed_to).to eq('escalate')
      end
    end

    context 'when confidence sits in the draft band (>=0.5 but < min_confidence)' do
      it 'parks for operator review (decision=operator_draft, stage unchanged)' do
        stub_classifier(intent_class: 'interested_commission', confidence: 0.7, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        expect(CampaignLlmDecision.last.routed_to).to eq('operator_draft')
        expect(participant.reload.next_action_at).to be_nil
        expect(participant.current_stage_key).to eq('reply_router')
      end
    end

    context 'with declined intent at >= 0.85 confidence (C7.3)' do
      it 'parks the participant in terminal without forcing opt-out or consent decline' do # rubocop:disable RSpec/MultipleExpectations
        participant.update!(conversation: conversation)
        stub_classifier(intent_class: 'declined', confidence: 0.9, model: 'stub-1')

        expect do
          described_class.new(participant: participant, stage: router_stage).call
        end.not_to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)

        expect(participant.reload).to be_paused
        expect(participant.current_stage_key).to eq('terminal')
        expect(participant.metadata['paused_reason']).to eq('declined_reply')
        expect(profile.reload).not_to be_do_not_contact
        expect(profile.marketing_consent_state).not_to eq('declined')
        expect(conversation.reload).to be_open
        expect(conversation.label_list).to include('outreach_replied')
        expect(conversation.label_list).not_to include('outreach_opt_out')
      end # rubocop:enable RSpec/MultipleExpectations

      it 'does NOT enqueue propagation for declined below threshold' do
        stub_classifier(intent_class: 'declined', confidence: 0.6, model: 'stub-1')

        expect do
          described_class.new(participant: participant, stage: router_stage).call
        end.not_to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)
      end
    end

    context 'when the intent class has no matching branch rule' do
      it 'escalates without crashing' do
        stub_classifier(intent_class: 'asks_showroom', confidence: 0.9, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        expect(participant.reload.current_stage_key).to eq('escalated')
        expect(CampaignLlmDecision.last.routed_to).to eq('escalate')
      end
    end
  end
end
