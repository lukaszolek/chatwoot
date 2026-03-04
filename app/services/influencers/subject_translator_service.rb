class Influencers::SubjectTranslatorService
  def initialize(account:, conversation:, target_locale:)
    @account = account
    @conversation = conversation
    @target_locale = target_locale
  end

  def perform
    return unless translatable?

    translated = translate(@hook, @subject)
    return if translated.blank?

    @conversation.update!(additional_attributes: @conversation.additional_attributes.merge('mail_subject' => translated))
  rescue StandardError => e
    Rails.logger.error "Subject translation failed for conversation #{@conversation.id}: #{e.message}"
  end

  private

  def translatable?
    return false if @target_locale.blank?

    @hook = @account.hooks.find_by(app_id: 'google_translate')
    return false if @hook.blank? || @hook.disabled?

    @subject = @conversation.additional_attributes&.dig('mail_subject')
    @subject.present?
  end

  def translate(hook, text)
    client = build_client(hook)
    project = "projects/#{hook.settings['project_id']}"

    source = detect_language(client, project, text)
    return if source == @target_locale

    response = client.translate_text(contents: [text], target_language_code: @target_locale, parent: project)
    response.translations&.first&.translated_text
  end

  def detect_language(client, project, text)
    detected = client.detect_language(content: text, parent: project)
    detected&.languages&.first&.language_code
  end

  def build_client(hook)
    ::Google::Cloud::Translate::V3::TranslationService::Client.new do |config|
      config.credentials = hook.settings['credentials']
    end
  end
end
