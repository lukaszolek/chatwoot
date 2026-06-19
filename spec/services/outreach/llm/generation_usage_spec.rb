# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Llm::GenerationUsage do
  describe '.fetch' do
    it 'extracts usage and cost directly from provider metadata raw_usage' do
      provider_metadata = {
        'raw_usage' => {
          'prompt_tokens' => 123,
          'completion_tokens' => 45,
          'total_cost' => '0.00123',
          'prompt_tokens_details' => {
            'cached_tokens' => 20,
            'cache_write_tokens' => 5
          }
        }
      }

      expect(Outreach::Llm::OpenRouterGenerationUsage).to receive(:fetch).with(nil).and_return(nil)

      result = described_class.fetch(provider_metadata)

      expect(result).to eq(
        'actual_cost_usd' => 0.00123,
        'native_prompt_tokens' => 123,
        'native_completion_tokens' => 45,
        'cached_tokens' => 20,
        'cache_write_tokens' => 5
      )
    end

    it 'merges inline usage with richer openrouter generation usage when available' do
      provider_metadata = {
        'generation_id' => 'gen-123',
        'raw_usage' => {
          'prompt_tokens' => 90,
          'completion_tokens' => 30,
          'total_cost' => '0.00080'
        }
      }

      expect(Outreach::Llm::OpenRouterGenerationUsage).to receive(:fetch).with('gen-123').and_return(
        'actual_cost_usd' => 0.00075,
        'provider_name' => 'openrouter',
        'cached_tokens' => 10
      )

      result = described_class.fetch(provider_metadata)

      expect(result).to eq(
        'actual_cost_usd' => 0.00075,
        'native_prompt_tokens' => 90,
        'native_completion_tokens' => 30,
        'provider_name' => 'openrouter',
        'cached_tokens' => 10
      )
    end
  end
end
