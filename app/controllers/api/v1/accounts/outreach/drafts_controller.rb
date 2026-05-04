class Api::V1::Accounts::Outreach::DraftsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  MAX_BULK_APPROVE = 100
  DEFAULT_BULK_APPROVE = 10

  def approve_pending
    result = Outreach::Drafts::BulkApproveService.new(
      campaign: campaign,
      user: Current.user,
      limit: bulk_approve_limit
    ).call
    render json: { result: result.to_h }, status: :ok
  end

  private

  def campaign
    @campaign ||= Current.account.outbound_campaigns.find_by!(program_key: program_key)
  end

  def program_key
    params[:program_key].presence || 'photographer_partnership'
  end

  def bulk_approve_limit
    requested = params[:limit].to_i
    requested = DEFAULT_BULK_APPROVE unless requested.positive?
    [requested, MAX_BULK_APPROVE].min
  end

  def check_authorization
    authorize(OutboundCampaign)
  end
end
