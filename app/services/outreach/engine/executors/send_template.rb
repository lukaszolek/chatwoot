# SendTemplate executor: renders the stage's template for the
# participant's locale, ensures Contact + Conversation exist, enqueues
# Outreach::SendEmailJob with the rendered subject/body, and transitions
# the participant to the stage's `next_stage_key`.
#
# Locale resolution prefers `participant.metadata['locale']`, falls back
# to the campaign's `config['default_locale']`, then the model default
# 'en'. If no template exists for the resolved (slot, locale) AND no
# fallback template for the campaign default_locale exists, the
# executor pauses the participant terminally — this is a blueprint bug
# the operator needs to fix.
class Outreach::Engine::Executors::SendTemplate < Outreach::Engine::Executors::Base
  def call
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

  private

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
