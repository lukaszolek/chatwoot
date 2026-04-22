# Returns the outreach context for a single conversation — campaign,
# participant, stage, and linked PhotographerPartnerProfile — used by
# the conversation sidebar panel in chatwoot UI.
#
# Returns 204 (no content) when the conversation is not linked to any
# outreach campaign, so the Vue side renders nothing without an error.
class Api::V1::Accounts::Outreach::ConversationContextsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :conversation

  def show
    participant_id = @conversation.additional_attributes.to_h['campaign_participant_id']
    return head :no_content if participant_id.blank?

    @participant = CampaignParticipant.find_by(id: participant_id, account_id: Current.account.id)
    return head :no_content unless @participant

    @campaign = @participant.outbound_campaign
    @stage = @campaign.pipeline_stages.find_by(key: @participant.current_stage_key)
    @profile = @participant.participatable if @participant.participatable.is_a?(PhotographerPartnerProfile)
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
