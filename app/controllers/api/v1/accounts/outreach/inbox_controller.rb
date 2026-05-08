class Api::V1::Accounts::Outreach::InboxController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def counts
    render json: Outreach::InboxCounts.new(user: Current.user).call
  end

  private

  def check_authorization
    authorize(OutboundCampaign)
  end
end
