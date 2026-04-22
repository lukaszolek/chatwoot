# Outbound mail delivery entry point.
#
# C3.1 skeleton: validates inputs, records `last_outbound_at`, and
# enqueues the existing chatwoot reply mailer through the campaign's
# inbox. No rate limiting, no List-Unsubscribe headers yet — those
# land in C3.2 along with HMAC unsubscribe tokens.
#
# Kept as a distinct job (rather than calling ConversationReplyMailer
# inline) so C3.2 can add rate-limit retry, header injection, and
# per-recipient-domain throttling in one place.
class Outreach::SendEmailJob < ApplicationJob
  queue_as :outreach

  # rubocop:disable Metrics/ParameterLists
  def perform(participant_id:, conversation_id:, subject:, body:, template_slot:, locale:)
    participant = CampaignParticipant.find_by(id: participant_id)
    return unless participant

    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    message = create_outgoing_message!(
      participant: participant,
      conversation: conversation,
      subject: subject,
      body: body,
      template_slot: template_slot,
      locale: locale
    )

    # update_columns skips validations/callbacks — last_outbound_at is an
    # audit field that must not re-run side effects on message create.
    participant.update_columns(last_outbound_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    Rails.logger.info(
      "[outreach.send_email] participant=#{participant.id} conversation=#{conversation.id} " \
      "slot=#{template_slot} locale=#{locale} message=#{message.id}"
    )
  end
  # rubocop:enable Metrics/ParameterLists

  private

  # rubocop:disable Metrics/ParameterLists
  def create_outgoing_message!(participant:, conversation:, subject:, body:, template_slot:, locale:)
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: body,
      content_type: 'text',
      sender: participant.outbound_campaign.sender_user,
      additional_attributes: {
        'outreach' => {
          'campaign_participant_id' => participant.id,
          'outbound_campaign_id' => participant.outbound_campaign_id,
          'template_slot' => template_slot,
          'locale' => locale,
          'subject' => subject
        }
      }
    )
  end
  # rubocop:enable Metrics/ParameterLists
end
