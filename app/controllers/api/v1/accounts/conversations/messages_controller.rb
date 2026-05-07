class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return render json: { content: message.translations[permitted_params[:target_language]] } if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  def approve_outreach_draft
    result = Outreach::Drafts::ApproveService.new(draft_message: message, user: Current.user).call
    render json: { ok: true, sent_message_id: result[:sent_message_id], draft_message_id: message.id }
  rescue Outreach::Drafts::ApproveService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def regenerate_outreach_draft
    result = Outreach::Drafts::RegenerateService.new(
      draft_message: message,
      user: Current.user,
      operator_prompt: params[:operator_prompt].to_s
    ).call
    render json: result
  rescue Outreach::Drafts::RegenerateService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reject_outreach_draft
    Outreach::Drafts::RejectService.new(
      draft_message: message,
      user: Current.user,
      reason: params[:reason].to_s
    ).call
    render json: { ok: true, draft_message_id: message.id }
  rescue Outreach::Drafts::RejectService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def edit_outreach_draft
    Outreach::Drafts::EditService.new(
      draft_message: message,
      user: Current.user,
      subject: params[:subject],
      body: params[:body],
      learning_note: params[:learning_note]
    ).call
    render json: { ok: true, draft_message_id: message.id }
  rescue Outreach::Drafts::EditService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
