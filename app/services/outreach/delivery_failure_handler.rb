# Keeps outreach campaign state aligned with the actual channel delivery
# result. Chatwoot creates the public outgoing Message before SMTP
# delivery completes; if SMTP later fails, the campaign must not keep
# behaving as if the slot was successfully sent.
class Outreach::DeliveryFailureHandler
  SUCCESS_STATUSES = %w[sent delivered read].freeze

  def initialize(message:, external_error: nil)
    @message = message
    @external_error = external_error
  end

  def call
    return unless outreach_delivery_message?

    participant = resolve_participant
    mark_conversation_failed!
    return unless participant

    restore_participant_to_failed_slot!(participant)
  rescue StandardError => e
    Rails.logger.warn(
      "[outreach.delivery_failure] message=#{message&.id} error=#{e.class}: #{e.message}"
    )
  end

  private

  attr_reader :message, :external_error

  def outreach_delivery_message?
    message.outgoing? && !message.private? && message.outreach_message?
  end

  def outreach_attrs
    @outreach_attrs ||= message.additional_attributes.to_h['outreach'].to_h
  end

  def resolve_participant
    id = outreach_attrs['campaign_participant_id']
    id.present? ? CampaignParticipant.find_by(id: id) : nil
  end

  def mark_conversation_failed!
    Outreach::ConversationLabels.mark_delivery_failed!(
      message.conversation,
      sent_successfully: successful_outreach_message_exists?
    )
  end

  def successful_outreach_message_exists?
    message.conversation.messages
           .where(message_type: :outgoing, private: false, status: SUCCESS_STATUSES)
           .where("messages.additional_attributes ? 'outreach'")
           .where.not(id: message.id)
           .exists?
  end

  def restore_participant_to_failed_slot!(participant)
    stage = delivery_stage(participant.outbound_campaign)
    return unless stage

    participant.update!(
      current_stage_key: stage.key,
      stage_entered_at: Time.current,
      next_action_at: nil,
      last_outbound_at: latest_successful_outbound_at,
      paused: false,
      metadata: failure_metadata(participant)
    )
  end

  def delivery_stage(campaign)
    campaign.pipeline_stages
            .send_template
            .find_by(template_slot: outreach_attrs['template_slot'].to_s)
  end

  def latest_successful_outbound_at
    message.conversation.messages
           .where(message_type: :outgoing, private: false, status: SUCCESS_STATUSES)
           .where("messages.additional_attributes ? 'outreach'")
           .where.not(id: message.id)
           .maximum(:created_at)
  end

  def failure_metadata(participant)
    participant.metadata.to_h.merge(
      'last_delivery_error' => external_error.to_s,
      'last_delivery_error_at' => Time.current.iso8601,
      'last_delivery_failed_message_id' => message.id,
      'last_delivery_failed_template_slot' => outreach_attrs['template_slot']
    )
  end
end
