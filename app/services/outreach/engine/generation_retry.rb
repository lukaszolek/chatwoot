class Outreach::Engine::GenerationRetry
  class UnknownErrorKind < ArgumentError; end

  RETRY_STAGE_BY_TEMPLATE_SLOT = {
    'intro' => 'intro',
    'reminder' => 'reminder_send',
    'breakup' => 'breakup_send'
  }.freeze

  ERROR_KIND_PATTERNS = {
    payment_required: ['%PaymentRequired%'],
    provider_error: ['%Provider returned error%'],
    all: ['%PaymentRequired%', '%Provider returned error%']
  }.freeze

  def self.candidate_scope(campaign, error_kind:)
    patterns = patterns_for(error_kind)
    base = campaign.participants
                   .where(current_stage_key: 'intro')
                   .where("metadata ? 'last_error'")

    return base if patterns.empty?

    patterns
      .map { |pattern| base.where("metadata->>'last_error' ILIKE ?", pattern) }
      .reduce { |scope, relation| scope.or(relation) }
  end

  def self.patterns_for(error_kind)
    case error_kind.to_s
    when '', 'payment_required', 'payment', 'llm_credits'
      ERROR_KIND_PATTERNS.fetch(:payment_required)
    when 'provider_error', 'provider'
      ERROR_KIND_PATTERNS.fetch(:provider_error)
    when 'all'
      ERROR_KIND_PATTERNS.fetch(:all)
    else
      raise UnknownErrorKind, "Unknown generation retry error kind: #{error_kind}"
    end
  end

  def initialize(participant)
    @participant = participant
  end

  def call
    stage_key = retry_stage_key
    participant.update!(
      current_stage_key: stage_key || participant.current_stage_key,
      paused: false,
      next_action_at: Time.current,
      metadata: participant.metadata.to_h.except(
        'last_error',
        'last_error_at',
        'processing_started_at'
      ).merge('generation_retry_requested_at' => Time.current.iso8601)
    )
  end

  private

  attr_reader :participant

  def retry_stage_key
    return participant.current_stage_key unless participant.current_stage_key == 'escalated'

    draft = last_rejected_draft
    RETRY_STAGE_BY_TEMPLATE_SLOT[draft&.additional_attributes&.[]('template_slot').to_s]
  end

  def last_rejected_draft
    return nil unless participant.conversation

    participant
      .conversation
      .messages
      .outreach_drafts
      .where("messages.additional_attributes->>'campaign_participant_id' = ?", participant.id.to_s)
      .where("messages.additional_attributes->>'draft_status' = 'rejected'")
      .order(created_at: :desc)
      .first
  end
end
