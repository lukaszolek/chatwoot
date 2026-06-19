require 'cgi'

class Outreach::Llm::OpenRouterGenerationUsage
  def self.fetch(generation_id)
    new(generation_id).fetch
  end

  def initialize(generation_id)
    @generation_id = generation_id.to_s
  end

  def fetch
    return nil if generation_id.blank?
    return nil unless openrouter_base?

    response = Faraday.get(generation_url) do |request|
      request.headers['Authorization'] = "Bearer #{api_key}"
      request.headers['Content-Type'] = 'application/json'
    end
    return nil unless response.success?

    normalize(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.warn("[outreach.openrouter.generation_usage] id=#{generation_id} error=#{e.class}: #{e.message.to_s.truncate(200)}")
    nil
  end

  private

  attr_reader :generation_id

  def normalize(payload)
    data = payload['data'] || payload
    {
      'actual_cost_usd' => number(data['total_cost'] || data['cost']),
      'cache_discount_usd' => number(data['cache_discount']),
      'provider_name' => data['provider_name'] || data['provider'],
      'generation_id' => generation_id,
      'native_prompt_tokens' => integer(data['native_tokens_prompt']),
      'native_completion_tokens' => integer(data['native_tokens_completion']),
      'cached_tokens' => integer(data['cached_tokens']),
      'cache_write_tokens' => integer(data['cache_write_tokens'])
    }.compact
  end

  def generation_url
    "#{base_url}/generation?id=#{CGI.escape(generation_id)}"
  end

  def base_url
    ENV.fetch('OUTREACH_LLM_BASE_URL', 'https://openrouter.ai/api/v1').sub(%r{/*\z}, '')
  end

  def openrouter_base?
    base_url.include?('openrouter.ai')
  end

  def api_key
    ENV.fetch('OUTREACH_LLM_API_KEY', nil)
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
