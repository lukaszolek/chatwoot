class Integrations::GoogleTranslate::DetectLanguageService
  pattr_initialize [:hook!, :message!]

  def perform
    return unless valid_message?
    return if conversation.additional_attributes['conversation_language'].present?

    language = Integrations::GoogleTranslate::GeminiClient.new(hook: hook).detect_language(message.content[0...1500])
    update_conversation(language)
  end

  private

  def valid_message?
    message.incoming? && message.content.present?
  end

  def conversation
    @conversation ||= message.conversation
  end

  def update_conversation(conversation_language)
    return if conversation_language.blank?

    additional_attributes = conversation.additional_attributes.merge({ conversation_language: conversation_language })
    conversation.update!(additional_attributes: additional_attributes)
    save_contact_locale(conversation_language)
  end

  def save_contact_locale(language)
    contact = conversation.contact
    return if contact.additional_attributes&.dig('locale').present?

    contact.update!(additional_attributes: (contact.additional_attributes || {}).merge('locale' => language))
  end
end
