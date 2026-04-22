# SendTemplate executor: renders the stage's template for the
# participant's locale, ensures Contact + Conversation exist, enqueues
# Outreach::SendEmailJob with the rendered subject/body, and transitions
# the participant to the stage's `next_stage_key`.
#
# Pacing guards before sending (requirements — photographer outreach is
# personal, not marketing):
#   - min gap: last_outbound_at must be >= MIN_GAP ago (or absent)
#   - reply-stop: if last_inbound_at > last_outbound_at, don't send;
#     the participant already replied, reply_router will pick it up
#   - cap: total outbound messages on this conversation < MAX_OUTBOUND
#
# When a guard trips we either (a) push next_action_at to the earliest
# allowed time and stay in the stage, or (b) pause terminally when the
# cap is hit / the participant replied. That way a stuck pipeline is
# always either waiting or terminal — never silently dropping messages.
#
# Locale resolution: participant.metadata['locale'] > participant's
# profile.preferred_language > campaign config default_locale > 'en'.
# When no template exists for the resolved (slot, locale) AND no
# fallback for the campaign default_locale exists, the executor pauses
# the participant terminally — this is a blueprint bug the operator
# needs to fix.
class Outreach::Engine::Executors::SendTemplate < Outreach::Engine::Executors::Base
  MAX_OUTBOUND = 3
  MIN_GAP = 7.days

  # rubocop:disable Metrics/MethodLength
  def call
    return skip_replied! if already_replied?
    return skip_cap! if outbound_count >= MAX_OUTBOUND
    return park_until_gap_elapsed! if gap_not_elapsed?

    template = resolve_template
    unless template
      pause_terminal!(reason: "no_template_for_slot:#{stage.template_slot}")
      return
    end

    rendered = Outreach::Engine::TemplateRenderer.new(
      template: template, participant: participant
    ).render

    conversation = Outreach::Engine::ConversationResolver.new(participant).conversation

    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: conversation.id,
      subject: rendered[:subject],
      body: rendered[:body],
      template_slot: template.slot,
      locale: template.locale
    )

    advance_after_send
  end
  # rubocop:enable Metrics/MethodLength

  private

  # ---------- pacing guards ----------

  def already_replied?
    participant.last_inbound_at.present? &&
      participant.last_outbound_at.present? &&
      participant.last_inbound_at > participant.last_outbound_at
  end

  def outbound_count
    return 0 unless participant.conversation_id

    participant.conversation.messages
               .where(message_type: :outgoing, private: false)
               .count
  end

  def gap_not_elapsed?
    return false if participant.last_outbound_at.blank?

    participant.last_outbound_at > MIN_GAP.ago
  end

  def skip_replied!
    pause_terminal!(reason: 'replied_before_send')
  end

  def skip_cap!
    pause_terminal!(reason: "outbound_cap_reached:#{MAX_OUTBOUND}")
  end

  def park_until_gap_elapsed!
    due_at = participant.last_outbound_at + MIN_GAP
    participant.update!(next_action_at: due_at)
  end

  # ---------- template resolution ----------

  def resolve_template
    slot = stage.template_slot
    locale = participant_locale
    template = CampaignTemplate.lookup(outbound_campaign: campaign, slot: slot, locale: locale)
    return template if template

    default_locale = campaign_default_locale
    return nil if default_locale.blank? || default_locale == locale

    CampaignTemplate.lookup(outbound_campaign: campaign, slot: slot, locale: default_locale)
  end

  def participant_locale
    (participant.metadata || {})['locale'].presence ||
      participant.participatable.try(:preferred_language).presence ||
      campaign_default_locale
  end

  def campaign_default_locale
    (campaign.config || {})['default_locale'].presence || 'en'
  end

  def advance_after_send
    if stage.next_stage_key.present?
      transition_to!(stage.next_stage_key)
    else
      pause_terminal!(reason: "send_without_next_stage:#{stage.key}")
    end
    participant.update!(last_outbound_at: Time.current)
  end
end
