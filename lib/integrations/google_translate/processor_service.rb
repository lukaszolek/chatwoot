class Integrations::GoogleTranslate::ProcessorService
  pattr_initialize [:message!, :target_language!]

  MAX_CONTENT_LENGTH = 30_000

  # Translates message.content: for emails that is the reply part only as
  # plain text, so quoted history and HTML markup are not paid for.
  def perform
    return if hook.blank?
    return if message.content.blank?

    content = message.content.truncate(MAX_CONTENT_LENGTH)
    Integrations::GoogleTranslate::GeminiClient.new(hook: hook).translate(content, target_language.tr('_', '-'))['translation']
  end

  private

  def hook
    @hook ||= message.account.hooks.find_by(app_id: 'google_translate')
  end
end
