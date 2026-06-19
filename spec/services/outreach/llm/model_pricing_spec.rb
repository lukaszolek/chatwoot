# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Llm::ModelPricing do
  describe '.estimate_usd' do
    it 'returns an estimate for deepseek v4 flash' do
      result = described_class.estimate_usd(
        model: 'deepseek/deepseek-v4-flash',
        token_usage: { 'prompt_tokens' => 1_000_000, 'completion_tokens' => 1_000_000 }
      )

      expect(result).to eq(0.42)
    end

    it 'supports env pricing overrides for models missing from the default table' do
      ClimateControl.modify(
        OUTREACH_LLM_MODEL_PRICING_JSON: '{"mistral-large-3":{"input":0.5,"output":1.5}}'
      ) do
        result = described_class.estimate_usd(
          model: 'mistral-large-3',
          token_usage: { 'prompt_tokens' => 2_000, 'completion_tokens' => 1_000 }
        )

        expect(result).to eq(0.0025)
      end
    end
  end
end
