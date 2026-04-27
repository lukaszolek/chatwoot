# Common base for every Outreach agent tool. Wraps execute! with the
# scope check + audit log + error normalization, so each subclass only
# implements the actual work and declares its params via RubyLLM::Tool's
# DSL (description / param).
class Outreach::Agent::Tools::Base < RubyLLM::Tool
  attr_reader :toolbox

  def initialize(toolbox:)
    @toolbox = toolbox
    super()
  end

  # Subclasses override; receive only validated params.
  # Must return a Hash that the LLM can read back as JSON.
  def execute!(_params)
    raise NotImplementedError
  end

  # Adapter from RubyLLM::Tool's #execute(**params) to our scope-checked
  # execute!. RubyLLM passes positional kwargs straight from the model's
  # tool-call args.
  def execute(**params)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    profile = toolbox.scope_to_sender!(params[:sender_email])
    result = execute!(**params, profile: profile)
    log_success(params, result, started)
    result
  rescue Outreach::Agent::Toolbox::ToolAuthorizationError => e
    log_failure(params, e, started, error_kind: :authorization)
    { error: 'forbidden', message: e.message }
  rescue StandardError => e
    log_failure(params, e, started, error_kind: :tool_failed)
    { error: 'tool_failed', message: e.message }
  end

  private

  def latency_ms_since(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  def log_success(params, result, started)
    toolbox.log!(
      tool_name: tool_log_name,
      params: params,
      result: result,
      success: true,
      latency_ms: latency_ms_since(started)
    )
  end

  def log_failure(params, error, started, error_kind:)
    toolbox.log!(
      tool_name: tool_log_name,
      params: params,
      result: { error_kind: error_kind.to_s },
      success: false,
      error_message: "#{error.class}: #{error.message}",
      latency_ms: latency_ms_since(started)
    )
  end

  def tool_log_name
    self.class.name.demodulize.underscore
  end
end
