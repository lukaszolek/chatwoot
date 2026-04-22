# Outbound mail delivery entry point for the outreach engine.
#
# Responsibilities:
#   1. Reserve a per-recipient-domain rate-limit token (Outreach::RateLimiter)
#      — if the hourly bucket is exhausted, re-enqueue with a 10-minute delay
#      and return without creating a Message.
#   2. Set the conversation's `mail_subject` so chatwoot's reply mailer
#      uses the outreach template's subject instead of its generic
#      "[#1542] New messages" fallback.
#   3. Create the outgoing Message on the participant's Conversation; the
#      mailer that fires off outgoing messages in chatwoot handles actual
#      SMTP delivery, including the campaign's configured email inbox.
#   4. Stamp participant.last_outbound_at and message.additional_attributes
#      with outreach metadata for downstream audits.
#
# Note on unsubscribe: outreach mails are personal — we don't append a
# List-Unsubscribe footer. If a recipient wants off, they reply and the
# operator flips them to do_not_contact. The unsubscribe endpoint + token
# service still exists (used by programmatic opt-outs and audits), but is
# not surfaced in outbound copy.
class Outreach::SendEmailJob < ApplicationJob
  queue_as :outreach

  RATE_LIMIT_RETRY_DELAY = 10.minutes

  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
  def perform(participant_id:, conversation_id:, subject:, body:, template_slot:, locale:)
    participant = CampaignParticipant.find_by(id: participant_id)
    return unless participant

    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    domain = Outreach::RateLimiter.domain_from_email(resolve_recipient_email(conversation, participant))

    unless rate_limiter(domain).reserve!
      reschedule(
        participant_id: participant_id, conversation_id: conversation_id,
        subject: subject, body: body, template_slot: template_slot, locale: locale,
        reason: "rate_limited:#{domain}"
      )
      return
    end

    set_conversation_mail_subject!(conversation, subject)
    message = create_outgoing_message!(
      participant: participant, conversation: conversation,
      subject: subject, body: body,
      template_slot: template_slot, locale: locale
    )

    # update_columns skips validations/callbacks — last_outbound_at is an
    # audit field that must not re-run side effects on message create.
    participant.update_columns(last_outbound_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    Rails.logger.info(
      "[outreach.send_email] participant=#{participant.id} conversation=#{conversation.id} " \
      "slot=#{template_slot} locale=#{locale} domain=#{domain} message=#{message.id}"
    )
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  private

  def rate_limiter(domain)
    Outreach::RateLimiter.new(domain, max_per_hour: max_per_hour)
  end

  def max_per_hour
    ENV.fetch('OUTREACH_MAX_PER_DOMAIN_PER_HOUR', Outreach::RateLimiter::DEFAULT_MAX_PER_HOUR).to_i
  end

  def resolve_recipient_email(conversation, participant)
    conversation.contact&.email.presence ||
      participant.participatable.try(:email).to_s
  end

  def reschedule(reason:, **kwargs)
    Rails.logger.info(
      "[outreach.send_email] rescheduling participant=#{kwargs[:participant_id]} reason=#{reason}"
    )
    self.class.set(wait: RATE_LIMIT_RETRY_DELAY).perform_later(**kwargs)
  end

  # Setting mail_subject on the conversation gets picked up by
  # ConversationReplyMailer#mail_subject, which prefixes "Re: " when
  # there's already chat history so reminder/breakup mails thread as
  # expected under the intro subject.
  def set_conversation_mail_subject!(conversation, subject)
    attrs = conversation.additional_attributes.to_h
    return if attrs['mail_subject'] == subject

    attrs['mail_subject'] = subject
    conversation.update_columns(additional_attributes: attrs, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

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
