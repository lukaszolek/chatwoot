# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Llm::DecisionLogger do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile)
  end

  describe '.record!' do
    it 'writes a CampaignLlmDecision with SHA-256 input_digest and token usage' do
      decision = described_class.record!(
        participant: participant,
        decision_type: :classify_reply,
        input: 'hello prompt',
        output: { 'intent_class' => 'interested_commission' },
        model: 'deepseek/deepseek-v3.2-exp',
        prompt_version: 'outreach.classify.v1',
        confidence: 0.92,
        routed_to: :auto_send,
        token_usage: { 'prompt_tokens' => 10 },
        latency_ms: 120
      )

      expect(decision).to be_persisted
      expect(decision.decision_type).to eq('classify_reply')
      expect(decision.input_digest).to eq(Digest::SHA256.hexdigest('hello prompt'))
      expect(decision.routed_to).to eq('auto_send')
      expect(decision.token_usage['prompt_tokens']).to eq(10)
    end
  end
end
