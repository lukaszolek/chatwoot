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
  end

  def stub_classifier(**outcome)
    classifier = instance_double(Outreach::Llm::ReplyClassifier, call: outcome)
    allow(Outreach::Llm::ReplyClassifier).to receive(:new).and_return(classifier)
  end

  describe '#call' do
    context 'when confidence >= rule.min_confidence' do
      it 'transitions to the rule target (auto_send)' do
        stub_classifier(
          intent_class: 'interested_commission', confidence: 0.95,
          model: 'stub-1', output: { 'reasoning' => 'clear yes' }
        )

        described_class.new(participant: participant, stage: router_stage).call

        expect(participant.reload.current_stage_key).to eq('auto_reply_commission')
        decision = CampaignLlmDecision.last
        expect(decision.routed_to).to eq('auto_send')
        expect(decision.confidence).to be_within(0.001).of(0.95)
      end
    end

    context 'when target is the escalated stage' do
      before do
        router_stage.update!(branch_rules: router_stage.branch_rules.merge(
          'interested_signup' => { 'target' => 'escalated', 'min_confidence' => 0.85 }
        ))
      end

      it 'records routed_to=escalate even when confidence passes the bar' do
        stub_classifier(intent_class: 'interested_signup', confidence: 0.9, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        expect(participant.reload.current_stage_key).to eq('escalated')
        expect(CampaignLlmDecision.last.routed_to).to eq('escalate')
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
      it 'falls back to escalation until C4.1 provides a draft composer' do
        stub_classifier(intent_class: 'interested_commission', confidence: 0.7, model: 'stub-1')

        described_class.new(participant: participant, stage: router_stage).call

        expect(participant.reload.current_stage_key).to eq('escalated')
        expect(participant.metadata['escalation_reason']).to start_with('operator_draft_pending_llm')
        expect(CampaignLlmDecision.last.routed_to).to eq('operator_draft')
      end
    end

    context 'with declined intent at >= 0.85 confidence (C7.3)' do
      it 'marks the conversation opt-out, pauses outreach, and propagates consent' do
        participant.update!(conversation: conversation)
        stub_classifier(intent_class: 'declined', confidence: 0.9, model: 'stub-1')

        expect do
          described_class.new(participant: participant, stage: router_stage).call
        end.to have_enqueued_job(Outreach::PhotographerDirectory::PropagateConsentJob)
          .with(profile.id, 'opt_out', reason: 'explicit_decline')

        expect(participant.reload).to be_paused
        expect(participant.current_stage_key).to eq('terminal')
        expect(profile.reload).to be_do_not_contact
        expect(profile).to be_consent_declined
        expect(conversation.reload).to be_resolved
        expect(conversation.label_list).to include('outreach_opt_out')
      end

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
