# Populates `message.content_attributes['translations']` with renderings
# of the message into every UI locale used by an agent on the account,
# so operators can read outreach messages (drafts + sent) in their
# language even when the LLM-generated copy is in the recipient's
# locale.
#
# Why this exists: outreach bypasses Messages::MessageBuilder (it calls
# `conversation.messages.create!` directly to keep the LLM-composed
# subject/body intact), so MessageBuilder#auto_translate_outgoing never
# runs and operators saw only the recipient-language original. This
# service plugs that hole for the outreach-only paths.
#
# Idempotent: skips locales that already have a translation; skips the
# source locale itself; no-ops when the google_translate hook is
# disabled or unconfigured. Failures are swallowed (logged) — translation
# is best-effort UI sugar, not a delivery-blocking step.
class Outreach::TranslateForAgents
  def self.call(message:, source_locale:)
    new(message: message, source_locale: source_locale).call
  end

  def initialize(message:, source_locale:)
    @message = message
    @source_locale = source_locale.to_s.presence
  end

  def call
    return unless @message&.content.present?
    return if hook.blank? || hook.disabled?
    return if target_locales.empty?

    update_translations!
  rescue StandardError => e
    Rails.logger.warn(
      "[outreach.translate_for_agents] failed message=#{@message&.id} " \
      "source=#{@source_locale}: #{e.class}: #{e.message.truncate(200)}"
    )
  end

  private

  def hook
    @hook ||= @message.account.hooks.find_by(app_id: 'google_translate')
  end

  def target_locales
    @target_locales ||= @message.account.users
                                .filter_map { |u| u.ui_settings&.dig('locale') }
                                .uniq
                                .compact
                                .reject { |l| l == @source_locale }
  end

  # Always rebuilds translations from current content. Callers that
  # mutate content (regenerate / edit) rely on this — stale renderings
  # from a previous body would be worse than missing ones.
  def update_translations!
    translations = {}
    target_locales.each do |lang|
      translated = Integrations::GoogleTranslate::ProcessorService.new(
        message: @message, target_language: lang
      ).perform
      translations[lang] = translated if translated.present?
    end

    return if translations.empty?

    @message.content_attributes ||= {}
    @message.content_attributes['translations'] = translations
    @message.save!
  end
end
