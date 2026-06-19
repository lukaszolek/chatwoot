class Outreach::Drafts::CompareModelsService
  class Error < StandardError; end

  DEFAULT_MODELS = %w[
    deepseek/deepseek-v4-flash
  ].freeze

  def self.default_models
    configured_models.presence || inferred_models
  end

  def initialize(draft_message:, models: self.class.default_models, operator_prompt: nil)
    @draft_message = draft_message
    @models = Array(models).map(&:to_s).map(&:strip).reject(&:blank?)
    @operator_prompt = operator_prompt.to_s.strip.presence
  end

  def call
    validate!

    comparison = build_started_comparison
    mark_comparison!(comparison)

    results = models.map { |model| compare_model(model) }
    comparison.merge!(
      'status' => 'completed',
      'completed_at' => Time.current.iso8601,
      'results' => results
    )
    mark_comparison!(comparison)
    comparison
  rescue StandardError => e
    mark_failed!(e)
    raise
  end

  private

  attr_reader :draft_message, :models, :operator_prompt

  def validate!
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'
    raise Error, 'no comparison models configured' if models.empty?
    raise Error, 'participant not found' unless participant
  end

  def participant
    @participant ||= begin
      pid = draft_message.additional_attributes['campaign_participant_id']
      pid ? CampaignParticipant.find_by(id: pid) : nil
    end
  end

  def slot
    @slot ||= draft_message.additional_attributes['template_slot'].to_s
  end

  def locale
    draft_message.additional_attributes['locale']
  end

  def build_started_comparison
    {
      'status' => 'processing',
      'started_at' => Time.current.iso8601,
      'slot' => slot,
      'locale' => locale,
      'models' => models,
      'operator_prompt' => operator_prompt,
      'results' => []
    }
  end

  def compare_model(model)
    composed = compose(model)
    raise Error, "composer_fallback:#{fallback_reason(composed)}" if composed[:fallback]

    model_result(model, composed)
  rescue StandardError => e
    {
      'ok' => false,
      'model' => model,
      'error' => "#{e.class}: #{e.message}".to_s.truncate(500)
    }
  end

  def model_result(model, composed)
    token_usage = composed[:token_usage] || {}
    provider_metadata = composed[:provider_metadata] || {}
    generation_usage = generation_usage(provider_metadata)
    {
      'ok' => true,
      'model' => model,
      'subject' => composed[:subject],
      'body' => legal_body(composed),
      'token_usage' => token_usage,
      'provider_metadata' => provider_metadata,
      'generation_usage' => generation_usage,
      'latency_ms' => composed[:latency_ms],
      'actual_cost_usd' => generation_usage&.dig('actual_cost_usd'),
      'estimated_cost_usd' => Outreach::Llm::ModelPricing.estimate_usd(model: model, token_usage: token_usage),
      'prompt_version' => composed[:prompt_version],
      'input_digest' => composed[:input_digest]
    }
  end

  def compose(model)
    case slot
    when 'intro'
      Outreach::Llm::MessageComposer::Intro.new(**composer_options(model)).call
    when 'reminder'
      Outreach::Llm::MessageComposer::Reminder.new(**composer_options(model)).call
    when 'breakup'
      Outreach::Llm::MessageComposer::Breakup.new(**composer_options(model)).call
    else
      raise Error, "unsupported comparison slot '#{slot}'"
    end
  end

  def generation_usage(provider_metadata)
    Outreach::Llm::GenerationUsage.fetch(provider_metadata)
  end

  def composer_options(model)
    {
      participant: participant,
      locale: locale,
      conversation: draft_message.conversation,
      operator_hint: operator_prompt,
      model: model
    }
  end

  def legal_body(composed)
    Outreach::LegalFooter.ensure_stop_opt_out(composed[:body], locale: composed[:locale] || locale)
  end

  def fallback_reason(composed)
    output = composed[:output]
    reason = output.is_a?(Hash) ? output['fallback'] : nil
    error_message = output.is_a?(Hash) ? output['error_message'] : nil
    [reason.presence || 'unknown', error_message.presence].compact.join(': ')
  end

  def mark_comparison!(comparison)
    additional = draft_message.additional_attributes.to_h.deep_dup
    additional['model_comparison'] = comparison
    draft_message.update!(additional_attributes: additional)
  end

  def mark_failed!(error)
    additional = draft_message.additional_attributes.to_h.deep_dup
    comparison = additional['model_comparison'].to_h
    comparison['status'] = 'failed'
    comparison['completed_at'] = Time.current.iso8601
    comparison['error'] = "#{error.class}: #{error.message}".to_s.truncate(500)
    additional['model_comparison'] = comparison
    draft_message.update!(additional_attributes: additional)
  rescue StandardError => e
    Rails.logger.warn("[outreach.drafts.compare_models] mark_failed_failed=#{e.class}: #{e.message.to_s.truncate(200)}")
  end

  class << self
    private

    def configured_models
      ENV.fetch('OUTREACH_LLM_COMPARE_MODELS', nil).to_s.split(',').map(&:strip).reject(&:blank?)
    end

    def inferred_models
      [
        Outreach::Llm::Client.new.draft_model,
        ENV.fetch('OUTREACH_LLM_COMPARE_ALT_MODEL', DEFAULT_MODELS.first)
      ].map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end
  end
end
