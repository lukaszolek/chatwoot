# Shared RubyLLM client for outreach LLM calls.
#
# Reads OpenRouter-compatible settings from OUTREACH_LLM_* env vars so
# outreach traffic can use a different provider (default: DeepSeek via
# OpenRouter, per §6.14 plan) than the main chatwoot LLM integration
# (captain / gpt-4.1-*).
#
# Calls are scoped via Llm::Config.with_api_key(...) so each call
# temporarily configures RubyLLM with outreach credentials without
# mutating the global client config.
#
# Subclasses build a system + user prompt, call `ask_json!`, and receive
# a parsed JSON hash + token usage + latency. They are responsible for
# schema-validating the hash and normalising to the DecisionLogger
# contract.
class Outreach::Llm::Client
  class LlmError < StandardError; end
  class InvalidJson < LlmError; end
  class ApiKeyMissing < LlmError; end

  def ask_json!(model:, system:, user:, temperature: 0.2)
    raise ApiKeyMissing, 'OUTREACH_LLM_API_KEY is not set' if api_key.blank?

    Llm::Config.initialize!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
      chat = context.chat(model: model).with_temperature(temperature)
      chat.with_instructions(system)
      chat.ask(user)
    end

    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    {
      parsed: parse_json!(response.content),
      raw_content: response.content,
      token_usage: {
        'prompt_tokens' => response.input_tokens,
        'completion_tokens' => response.output_tokens
      },
      latency_ms: latency_ms
    }
  end

  def compose_model
    ENV.fetch('OUTREACH_LLM_COMPOSE_MODEL', 'deepseek/deepseek-v3.2-exp')
  end

  def classify_model
    ENV.fetch('OUTREACH_LLM_CLASSIFY_MODEL', 'deepseek/deepseek-v3.2-exp')
  end

  def draft_model
    ENV.fetch('OUTREACH_LLM_DRAFT_MODEL', 'deepseek/deepseek-v3.2-exp')
  end

  private

  def api_key
    ENV.fetch('OUTREACH_LLM_API_KEY', nil)
  end

  def api_base
    ENV.fetch('OUTREACH_LLM_BASE_URL', 'https://openrouter.ai/api/v1')
  end

  def parse_json!(content)
    stripped = content.to_s.strip.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, '')
    JSON.parse(stripped)
  rescue JSON::ParserError => e
    raise InvalidJson, "LLM returned non-JSON response (#{e.message}): #{content.truncate(200)}"
  end
end
