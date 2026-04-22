# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::Executors::EscalateToUser do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account) }
  let(:campaign) { create(:outbound_campaign, account: account, sender_user: operator) }
  let(:stage) do
    create(:campaign_pipeline_stage,
           outbound_campaign: campaign,
           key: 'escalated',
           on_enter_action: :escalate_to_user,
           position: 9)
  end

  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:contact) { create(:contact, account: account, email: profile.email) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           participatable: profile,
           contact: contact,
           conversation: conversation,
           current_stage_key: 'escalated',
           metadata: { 'escalation_reason' => 'classifier_low_confidence:unclear' })
  end

  describe '#call' do
    it 'assigns the conversation to the campaign sender and adds a private note' do
      expect { described_class.new(participant: participant, stage: stage).call }
        .to change { conversation.reload.messages.where(private: true).count }.by(1)

      expect(conversation.reload.assignee_id).to eq(operator.id)
      expect(participant.reload.paused).to be(true)
      expect(participant.metadata['paused_reason']).to eq('escalated:escalated')
    end

    context 'when the participant has no conversation yet' do
      let(:participant) do
        create(:campaign_participant,
               outbound_campaign: campaign,
               account: account,
               participatable: profile,
               current_stage_key: 'escalated')
      end

      it 'still pauses the participant without raising' do
        expect { described_class.new(participant: participant, stage: stage).call }.not_to raise_error
        expect(participant.reload.paused).to be(true)
      end
    end
  end
end
