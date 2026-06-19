class Outreach::Llm::ModelPricing
  DEFAULT_PRICE_PER_MILLION_TOKENS = {
    'qwen/qwen3.6-plus' => { input: 0.325, output: 1.95 },
    'moonshotai/kimi-k2.6' => { input: 0.74, output: 3.50 },
    'deepseek/deepseek-v4-pro' => { input: 0.435, output: 0.87 },
    'deepseek/deepseek-v4-flash' => { input: 0.14, output: 0.28 }
  }.freeze

  def self.estimate_usd(model:, token_usage:)
    pricing = price_table[model.to_s]
    return nil unless pricing

    prompt_tokens = token_usage.to_h['prompt_tokens'].to_i
    completion_tokens = token_usage.to_h['completion_tokens'].to_i

    ((prompt_tokens * pricing[:input]) + (completion_tokens * pricing[:output])) / 1_000_000.0
  end

  def self.price_table
    DEFAULT_PRICE_PER_MILLION_TOKENS.merge(env_overrides)
  end

  def self.env_overrides
    parsed_env_overrides.each_with_object({}) do |(model, pricing), acc|
      normalized = normalize_pricing(pricing)
      next if normalized.nil?

      acc[model.to_s] = normalized
    end
  rescue JSON::ParserError
    {}
  end

  def self.parsed_env_overrides
    raw = ENV.fetch('OUTREACH_LLM_MODEL_PRICING_JSON', nil).to_s.strip
    return {} if raw.blank?

    JSON.parse(raw)
  end

  def self.normalize_pricing(pricing)
    return nil unless pricing.is_a?(Hash)

    input = decimal(pricing['input'] || pricing[:input])
    output = decimal(pricing['output'] || pricing[:output])
    return nil if input.nil? || output.nil?

    { input: input, output: output }
  end

  def self.decimal(value)
    return nil if value.blank?

    BigDecimal(value.to_s).to_f
  rescue ArgumentError
    nil
  end
  private_class_method :decimal, :normalize_pricing, :parsed_env_overrides
end
