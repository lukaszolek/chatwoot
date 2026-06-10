class Outreach::Engine::ParticipantErrorState
  SUCCESS_METADATA_KEYS = %w[
    last_error
    last_error_details
    last_error_at
    processing_started_at
    processing_reason
    processing_reclaimed_at
    processing_reclaim_reason
  ].freeze

  def self.invalid_email_error?(error)
    return false unless error.is_a?(ActiveRecord::RecordInvalid)
    return true if error.record&.errors&.attribute_names&.include?(:email)

    error.message.to_s.match?(/email invalid email/i)
  end

  def initialize(participant)
    @participant = participant
  end

  def clear_success!
    participant.reload
    metadata = participant.metadata.to_h.except(*SUCCESS_METADATA_KEYS)
    Outreach::ConversationLabels.clear_error!(participant.conversation) if participant.conversation_id
    return if metadata == participant.metadata

    participant.update_columns(metadata: metadata, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[outreach.participant_error_state] clear_success! failed participant=#{participant.id}: #{e.message}")
  end

  def pause_invalid_email!(error:)
    metadata = (participant.metadata || {}).merge(
      'last_error' => error_reason(error),
      'last_error_at' => Time.current.iso8601,
      'terminal_error' => 'invalid_email',
      'terminal_error_at' => Time.current.iso8601
    )
    Outreach::ConversationLabels.mark_error!(participant.conversation) if participant.conversation_id
    participant.update_columns( # rubocop:disable Rails/SkipsModelValidations
      paused: true, next_action_at: nil, metadata: metadata, updated_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[outreach.participant_error_state] pause_invalid_email! failed participant=#{participant.id}: #{e.message}")
  end

  def back_off!(reason:, delay:, error: nil)
    metadata = (participant.metadata || {}).merge('last_error' => reason, 'last_error_at' => Time.current.iso8601)
    details = error_details(error)
    metadata = details.present? ? metadata.merge('last_error_details' => details) : metadata.except('last_error_details')
    Outreach::ConversationLabels.mark_error!(participant.conversation) if participant.conversation_id
    participant.update_columns( # rubocop:disable Rails/SkipsModelValidations
      next_action_at: Time.current + delay,
      metadata: metadata,
      updated_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[outreach.participant_error_state] back_off! failed participant=#{participant.id}: #{e.message}")
  end

  private

  attr_reader :participant

  def error_reason(error)
    message = error.message.to_s.squish.truncate(240)
    "executor_error:#{error.class.name}:#{message}"
  end

  def error_details(error)
    return nil unless error

    response = error.respond_to?(:response) ? error.response : nil
    {
      'class' => error.class.name,
      'message' => error.message.to_s.truncate(1000),
      'http_status' => response&.status,
      'response_body' => response_body(response),
      'response_headers' => response_headers(response)
    }.compact
  end

  def response_body(response)
    return nil unless response.respond_to?(:body)

    response.body.to_s.truncate(4000)
  end

  def response_headers(response)
    return nil unless response.respond_to?(:headers)

    response.headers.to_h.slice(
      'x-request-id',
      'x-generation-id',
      'cf-ray',
      'openrouter-provider',
      'content-type'
    ).compact
  end
end
