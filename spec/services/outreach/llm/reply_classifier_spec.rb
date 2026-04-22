# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Llm::ReplyClassifier do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile,
           current_stage_key: 'reply_router')
  end

  def stub_client_json(parsed)
    allow_any_instance_of(Outreach::Llm::Client).to receive(:ask_json!).and_return( # rubocop:disable RSpec/AnyInstance
      {
        parsed: parsed,
        raw_content: parsed.to_json,
        token_usage: { 'prompt_tokens' => 120, 'completion_tokens' => 40 },
        latency_ms: 220
      }
    )
  end

  describe '#call' do
    it 'returns normalised outcome with intent_class, confidence, audit metadata' do
      stub_client_json(
        'intent_class' => 'interested_commission',
        'confidence' => 0.92,
        'reasoning' => 'asks about %'
      )

      outcome = described_class.new(participant: participant).call
      expect(outcome[:intent_class]).to eq('interested_commission')
      expect(outcome[:confidence]).to be_within(0.001).of(0.92)
      expect(outcome[:model]).to be_present
      expect(outcome[:prompt_version]).to eq(described_class::PROMPT_VERSION)
      expect(outcome[:input_digest]).to match(/\A[a-f0-9]{64}\z/)
      expect(outcome[:token_usage]['prompt_tokens']).to eq(120)
      expect(outcome[:latency_ms]).to eq(220)
    end

    it 'coerces an unknown intent class to unclear with zero confidence' do
      stub_client_json('intent_class' => 'bogus_class', 'confidence' => 0.99, 'reasoning' => '')

      outcome = described_class.new(participant: participant).call
      expect(outcome[:intent_class]).to eq('unclear')
      expect(outcome[:confidence]).to eq(0.99)
    end

    it 'swallows LLM errors and falls back to unclear/0.0' do
      allow_any_instance_of(Outreach::Llm::Client).to receive(:ask_json!) # rubocop:disable RSpec/AnyInstance
        .and_raise(Outreach::Llm::Client::ApiKeyMissing, 'no key')

      outcome = described_class.new(participant: participant).call
      expect(outcome[:intent_class]).to eq('unclear')
      expect(outcome[:confidence]).to eq(0.0)
      expect(outcome[:reasoning]).to start_with('llm_error:')
    end
  end
end
