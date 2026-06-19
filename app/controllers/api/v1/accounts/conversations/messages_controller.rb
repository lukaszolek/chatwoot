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
    operator_prompt = params[:operator_prompt].to_s
    raise Outreach::Drafts::RegenerateService::Error, 'operator_prompt is required' if operator_prompt.strip.empty?

    mark_outreach_regeneration_queued!(message)
    Outreach::RegenerateDraftJob.perform_later(
      draft_message_id: message.id,
      user_id: Current.user&.id,
      operator_prompt: operator_prompt
    )
    render json: { ok: true, queued: true, draft_message_id: message.id }, status: :accepted
  rescue Outreach::Drafts::RegenerateService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Rack::Timeout::RequestTimeoutException => e
    render_regenerate_timeout(e)
  rescue StandardError => e
    render_regenerate_unexpected_error(e)
  end

  def compare_outreach_draft_models
    mark_outreach_model_comparison_queued!(message)
    Outreach::CompareDraftModelsJob.perform_later(
      draft_message_id: message.id,
      models: comparison_models,
      operator_prompt: params[:operator_prompt].presence
    )
    render json: { ok: true, queued: true, draft_message_id: message.id }, status: :accepted
  rescue Outreach::Drafts::CompareModelsService::Error, Outreach::Drafts::RegenerateService::Error => e
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

  def delete_outreach_draft
    Outreach::Drafts::DiscardService.new(
      draft_message: message,
      user: Current.user,
      reason: 'manual_delete'
    ).call
    render json: { ok: true, draft_message_id: message.id }
  rescue Outreach::Drafts::DiscardService::Error => e
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

  def render_regenerate_timeout(error)
    Rails.logger.warn(
      "[outreach.drafts.regenerate] message=#{params[:id]} conversation=#{params[:conversation_id]} " \
      "timeout=#{error.class}: #{error.message}"
    )
    render json: {
      error: 'LLM regeneration timed out before Chatwoot could finish the request. Draft was not changed.'
    }, status: :gateway_timeout
  end

  def render_regenerate_unexpected_error(error)
    Rails.logger.warn(
      "[outreach.drafts.regenerate] message=#{params[:id]} conversation=#{params[:conversation_id]} " \
      "error=#{error.class}: #{error.message}\n#{error.backtrace&.first(8)&.join("\n")}"
    )
    render json: {
      error: "LLM regeneration failed (unexpected_error:#{error.class}: #{error.message}). Draft may not have changed."
    }, status: :unprocessable_entity
  end

  def mark_outreach_regeneration_queued!(draft_message)
    raise Outreach::Drafts::RegenerateService::Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Outreach::Drafts::RegenerateService::Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'

    additional = draft_message.additional_attributes.to_h.deep_dup
    if %w[queued processing].include?(additional['regeneration_status'])
      raise Outreach::Drafts::RegenerateService::Error, 'draft regeneration already in progress'
    end

    additional['regeneration_status'] = 'queued'
    additional['regeneration_error'] = nil
    additional['regeneration_updated_at'] = Time.current.iso8601
    draft_message.update!(additional_attributes: additional)
  end

  def mark_outreach_model_comparison_queued!(draft_message)
    raise Outreach::Drafts::RegenerateService::Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Outreach::Drafts::RegenerateService::Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'

    additional = draft_message.additional_attributes.to_h.deep_dup
    comparison = additional['model_comparison'].to_h
    raise Outreach::Drafts::RegenerateService::Error, 'model comparison already in progress' \
      if %w[queued processing].include?(comparison['status'])

    additional['model_comparison'] = {
      'status' => 'queued',
      'queued_at' => Time.current.iso8601,
      'models' => comparison_models
    }
    draft_message.update!(additional_attributes: additional)
  end

  def comparison_models
    requested = params[:models]
    models = requested.is_a?(Array) ? requested : []
    models.map(&:to_s).map(&:strip).reject(&:blank?).presence ||
      Outreach::Drafts::CompareModelsService.default_models
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
