class Outreach::Llm::GenerationUsage
  class << self
    def fetch(provider_metadata)
      provider_metadata = provider_metadata.to_h

      inline_usage = from_raw_usage(provider_metadata['raw_usage'])
      fetched_usage = Outreach::Llm::OpenRouterGenerationUsage.fetch(provider_metadata['generation_id'])

      return fetched_usage if inline_usage.blank?
      return inline_usage if fetched_usage.blank?

      inline_usage.merge(fetched_usage.compact)
    end

    private

    def from_raw_usage(raw_usage)
      usage = raw_usage.to_h
      return nil if usage.blank?

      {
        'actual_cost_usd' => number(first_present(usage, %w[total_cost cost actual_cost estimated_cost total_price price])),
        'native_prompt_tokens' => integer(first_present(usage, %w[prompt_tokens input_tokens])),
        'native_completion_tokens' => integer(first_present(usage, %w[completion_tokens output_tokens])),
        'cached_tokens' => integer(dig_value(usage, %w[prompt_tokens_details cached_tokens])),
        'cache_write_tokens' => integer(dig_value(usage, %w[prompt_tokens_details cache_write_tokens]))
      }.compact.presence
    end

    def first_present(payload, keys)
      keys.lazy.map { |key| payload[key] }.find(&:present?)
    end

    def dig_value(payload, path)
      path.reduce(payload) do |acc, segment|
        break nil unless acc.is_a?(Hash)

        acc[segment]
      end
    end

    def number(value)
      return nil if value.blank?

      BigDecimal(value.to_s).to_f
    rescue ArgumentError
      nil
    end

    def integer(value)
      return nil if value.blank?

      value.to_i
    end
  end
end
