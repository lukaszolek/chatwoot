class Api::V1::Accounts::Outreach::CampaignsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :campaign, except: [:index]

  def index
    @campaigns = Current.account.outbound_campaigns.order(:name)
  end

  def show; end

  def pause
    @campaign.update!(status: :paused)
    render :show
  end

  def resume
    @campaign.update!(status: :active)
    render :show
  end

  def archive
    @campaign.update!(status: :archived)
    render :show
  end

  private

  def campaign
    @campaign ||= Current.account.outbound_campaigns.find(params[:id])
  end

  def check_authorization
    authorize(OutboundCampaign)
  end
end
