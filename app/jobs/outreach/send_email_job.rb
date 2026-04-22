# Outbound mail delivery entry point for the outreach engine.
#
# Responsibilities:
#   1. Reserve a per-recipient-domain rate-limit token (Outreach::RateLimiter)
#      — if the hourly bucket is exhausted, re-enqueue with a 10-minute delay
#      and return without creating a Message.
#   2. Mint a one-click unsubscribe URL (Outreach::UnsubscribeToken) and
#      append a footer to the body so recipients always have a way out.
#   3. Create the outgoing Message on the participant's Conversation; the
#      mailer that fires off outgoing messages in chatwoot handles actual
#      SMTP delivery, including the campaign's configured email inbox.
#   4. Stamp participant.last_outbound_at and message.additional_attributes
#      with outreach metadata for downstream audits and bounce handling.
#
# Kept as a distinct job (rather than calling ConversationReplyMailer
# inline) so that rate-limit + unsubscribe-token logic lives in one place
# and outreach sends never mix with generic chatwoot replies.
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

    unsubscribe_url = build_unsubscribe_url(participant)
    message = create_outgoing_message!(
      participant: participant, conversation: conversation,
      subject: subject, body: append_unsubscribe_footer(body, unsubscribe_url, locale),
      template_slot: template_slot, locale: locale,
      unsubscribe_url: unsubscribe_url
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

  def build_unsubscribe_url(participant)
    token = Outreach::UnsubscribeToken.sign(
      participant_id: participant.id,
      campaign_id: participant.outbound_campaign_id
    )
    host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000').chomp('/')
    "#{host}/unsubscribe/#{token}"
  rescue Outreach::UnsubscribeToken::SecretMissing => e
    Rails.logger.warn("[outreach.send_email] unsubscribe disabled: #{e.message}")
    nil
  end

  def append_unsubscribe_footer(body, url, _locale)
    return body if url.blank?

    footer = "\n\n---\nAby zrezygnować z tej korespondencji kliknij: #{url}\nTo unsubscribe from this outreach click: #{url}\n"
    "#{body}#{footer}"
  end

  # rubocop:disable Metrics/ParameterLists
  def create_outgoing_message!(participant:, conversation:, subject:, body:, template_slot:, locale:, unsubscribe_url:)
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
          'subject' => subject,
          'unsubscribe_url' => unsubscribe_url
        }.compact
      }
    )
  end
  # rubocop:enable Metrics/ParameterLists
end
