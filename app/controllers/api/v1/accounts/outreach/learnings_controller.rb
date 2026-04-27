# Operator-facing list / edit / delete for OutboundCampaignLearning rows.
# Learnings are written automatically by Outreach::Drafts::EditService and
# Outreach::Drafts::RegenerateService; operators can also dial them down
# (active=false) or rewrite content for clarity. Composers consume the
# active rows via OutboundCampaign#recent_learnings.
class Api::V1::Accounts::Outreach::LearningsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :campaign
  before_action :learning, only: [:update, :destroy]

  def index
    scope = @campaign.learnings.order(created_at: :desc)
    scope = scope.where(active: true) if params[:active] == 'true'
    scope = scope.where(slot: params[:slot]) if params[:slot].present?
    scope = scope.where(source_kind: params[:source_kind]) if params[:source_kind].present?
    @learnings = scope.limit((params[:limit] || 100).to_i)
  end

  def update
    @learning.update!(learning_params)
    render :show
  end

  def destroy
    @learning.destroy!
    head :no_content
  end

  private

  def campaign
    @campaign ||= Current.account.outbound_campaigns.find(params[:campaign_id])
  end

  def learning
    @learning ||= @campaign.learnings.find(params[:id])
  end

  def learning_params
    params.require(:outbound_campaign_learning).permit(:content, :active, :slot, :locale)
  end

  def check_authorization
    authorize(OutboundCampaign)
  end
end
