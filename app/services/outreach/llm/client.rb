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

    response = with_outreach_context(model: model) do |chat|
      configure_chat(chat, temperature: temperature, system: system)
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

  # Same as ask_json! but registers a set of RubyLLM::Tool subclasses so
  # the model can invoke them mid-turn. Tools are pre-constructed by the
  # caller so they already carry the scoped_sender_email + account context
  # — the LLM can never widen scope through params (the tool ignores any
  # email/profile_id it disagrees with and refuses with success: false).
  #
  # Returns the same shape as ask_json! plus :tool_calls (array of
  # {name, params, result, success}) for audit trace inspection.
  def ask_with_tools!(model:, system:, user:, tools:, temperature: 0.3)
    raise ApiKeyMissing, 'OUTREACH_LLM_API_KEY is not set' if api_key.blank?

    Llm::Config.initialize!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    captured_calls = []

    response = with_outreach_context(model: model) do |chat|
      configure_chat(chat, temperature: temperature, system: system)
      tools.each { |tool| chat.with_tool(tool) }
      chat.on_tool_call { |tc| captured_calls << { name: tc.name, params: tc.arguments } }
      chat.ask(user)
    end

    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    tool_response_payload(response, captured_calls, latency_ms)
  end

  # Scopes RubyLLM config to outreach credentials for the duration of
  # the block. Routes by provider — OpenRouter (default) uses its own
  # env keys (openrouter_api_key / openrouter_api_base), OpenAI-compat
  # falls back to Llm::Config.with_api_key which wires openai_*.
  def with_outreach_context(model:)
    if openrouter?
      context = RubyLLM.context do |config|
        config.openrouter_api_key = api_key
      end
      yield context.chat(model: model, provider: :openrouter, assume_model_exists: true)
    else
      # OpenAI-compatible gateways (eurouter.ai, custom proxies, etc.)
      # use OpenAI's request shape but with their own model IDs.
      # - assume_model_exists bypasses RubyLLM's built-in model registry
      #   so arbitrary model slugs (mistral-large-3, deepseek-v3, …) work
      # - openai_use_system_role = true forces role="system" for
      #   instructions; otherwise RubyLLM sends role="developer" (newer
      #   OpenAI API) which non-OpenAI models (mistral, deepseek)
      #   reject with 400/502.
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base if api_base.present?
        config.openai_use_system_role = true
      end
      yield context.chat(model: model, provider: :openai, assume_model_exists: true)
    end
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

  def openrouter?
    ENV.fetch('OUTREACH_LLM_PROVIDER', 'openrouter').to_s.downcase == 'openrouter'
  end

  def max_tokens
    ENV.fetch('OUTREACH_LLM_MAX_TOKENS', 2000).to_i
  end

  def configure_chat(chat, temperature:, system:)
    chat.with_temperature(temperature)
    chat.with_params(max_tokens: max_tokens)
    chat.with_instructions(system)
  end

  def tool_response_payload(response, captured_calls, latency_ms)
    {
      parsed: try_parse_json(response.content),
      raw_content: response.content,
      tool_calls: captured_calls,
      token_usage: {
        'prompt_tokens' => response.input_tokens,
        'completion_tokens' => response.output_tokens
      },
      latency_ms: latency_ms
    }
  end

  def parse_json!(content)
    stripped = content.to_s.strip.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, '')
    JSON.parse(stripped)
  rescue JSON::ParserError => e
    raise InvalidJson, "LLM returned non-JSON response (#{e.message}): #{content.truncate(200)}"
  end

  # Soft variant for ask_with_tools — when the model responds with prose
  # after a tool chain, that's expected (it's the answer to the user). We
  # still try to parse JSON in case the composer happens to emit one.
  def try_parse_json(content)
    parse_json!(content)
  rescue InvalidJson
    nil
  end
end
