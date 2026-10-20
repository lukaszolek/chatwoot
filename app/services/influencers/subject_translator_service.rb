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
    target = @target_locale.tr('_', '-')
    result = Integrations::GoogleTranslate::GeminiClient.new(hook: hook).translate(text, target)
    return if result['language'].to_s.split('-').first == target.split('-').first

    result['translation']
  end
end
