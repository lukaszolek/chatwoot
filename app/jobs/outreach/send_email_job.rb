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
    Outreach::TranslateForAgents.call(message: message, source_locale: locale)

    # update_columns skips validations/callbacks — last_outbound_at is an
    # audit field that must not re-run side effects on message create.
    advance_participant_after_send!(participant)

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
  # there's already chat history so reminder/breakup/reply mails thread
  # as expected under the intro subject.
  #
  # IMPORTANT: set ONLY ONCE per conversation. If we overwrote it on
  # every send, a reply (whose composer-generated subject differs from
  # intro's) would produce "Re: <new subject>" — Gmail and other clients
  # group threads by normalized subject, so a different subject lands
  # in a brand-new conversation in the recipient's inbox. Thread broken.
  def set_conversation_mail_subject!(conversation, subject)
    attrs = conversation.additional_attributes.to_h
    return if attrs['mail_subject'].present?

    attrs['mail_subject'] = subject
    conversation.update_columns(additional_attributes: attrs, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # rubocop:disable Metrics/ParameterLists
  def create_outgoing_message!(participant:, conversation:, subject:, body:, template_slot:, locale:)
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: normalize_for_email(body),
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

  def advance_participant_after_send!(participant)
    stage = participant.outbound_campaign.pipeline_stages.find_by(key: participant.current_stage_key)
    next_key = stage&.next_stage_key.presence || 'terminal'
    participant.update!(
      current_stage_key: next_key,
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      last_outbound_at: Time.current
    )
  end

  # The chatwoot reply mailer renders message.content through CommonMark
  # (ChatwootMarkdownRenderer). CommonMark collapses single-newline runs
  # into one paragraph, so a body like
  #
  #   Co z tego masz:
  #   • punkt 1
  #   • punkt 2
  #
  # ends up as a single mashed-together paragraph in the recipient's
  # inbox. We normalize defensively here so the receiver always sees
  # paragraph breaks, regardless of how disciplined the LLM was about
  # following the markdown rules in `tone` / `intro_seed`.
  #
  # Two transforms:
  #   1. Replace '•' Unicode bullets with '-' so CommonMark renders a
  #      proper <ul><li>.
  #   2. Insert a blank line before any contiguous bullet block and
  #      after it (only when missing) so the list is a separate
  #      markdown construct.
  #   3. For non-list runs of single-newline lines (e.g. a signature),
  #      append two trailing spaces to each non-blank line so CommonMark
  #      emits <br>.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def normalize_for_email(body)
    return body if body.blank?

    text = body.gsub(/^[ \t]*•[ \t]+/, '- ')

    lines = text.split("\n", -1)
    out = []
    in_list = false
    lines.each_with_index do |line, idx|
      bullet = line.lstrip.start_with?('- ')
      prev_blank = (idx.zero? || lines[idx - 1].strip.empty?)
      next_line = lines[idx + 1] || ''

      if bullet && !in_list
        out << '' unless prev_blank || out.last == ''
        in_list = true
      elsif !bullet && in_list && !line.strip.empty?
        out << '' if out.last != ''
        in_list = false
      elsif !bullet && line.strip.empty?
        in_list = false
      end

      # Markdown line-break (two trailing spaces) for non-list, non-blank
      # lines whose neighbour is also a non-blank, non-list line — keeps
      # signature blocks on separate visible lines.
      decorated = line
      if !bullet && !line.strip.empty? && next_line.present? && !next_line.strip.empty? && !next_line.lstrip.start_with?('- ')
        decorated = "#{line.rstrip}  "
      end
      out << decorated
    end
    out.join("\n")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
