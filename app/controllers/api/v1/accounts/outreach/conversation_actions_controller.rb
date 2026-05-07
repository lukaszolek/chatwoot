class Api::V1::Accounts::Outreach::ConversationActionsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :conversation

  def create
    Outreach::ConversationActionService.new(
      conversation: @conversation,
      action: params[:operation],
      user: Current.user
    ).call
    render json: { ok: true }, status: :ok
  rescue Outreach::ConversationActionService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id]) ||
                      Current.account.conversations.find_by(id: params[:conversation_id])
    raise ActiveRecord::RecordNotFound unless @conversation
  end

  def check_authorization
    authorize(OutboundCampaign)
  end
end
