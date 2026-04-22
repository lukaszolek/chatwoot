class Api::V1::Accounts::Outreach::PhotographerPartnerProfilesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :profile, except: [:index]

  PER_PAGE = 50

  def index
    scope = apply_filters(Current.account.photographer_partner_profiles.order(created_at: :desc))
    @total = scope.count
    @profiles = scope.limit(PER_PAGE).offset(((params[:page] || 1).to_i - 1) * PER_PAGE)
  end

  def show; end

  def update
    @profile.update!(profile_params)
    render :show
  end

  def opt_out
    reason = params[:reason].presence || 'operator_manual'
    ActiveRecord::Base.transaction do
      @profile.transition_to!(:do_not_contact) unless @profile.do_not_contact?
      CampaignParticipant.where(participatable: @profile, paused: false).update_all( # rubocop:disable Rails/SkipsModelValidations
        paused: true, updated_at: Time.current
      )
    end
    Outreach::PhotographerDirectory::PropagateConsentJob.perform_later(@profile.id, 'opt_out', reason: reason)
    render :show
  end

  private

  def apply_filters(scope)
    scope = scope.where(partnership_status: params[:status]) if params[:status].present?
    scope = scope.where(country_code: params[:country_code]) if params[:country_code].present?
    scope = scope.where(preferred_language: params[:locale]) if params[:locale].present?
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where('email ILIKE :q OR business_name ILIKE :q OR owner_name ILIKE :q', q: q)
    end
    scope
  end

  def profile
    @profile ||= Current.account.photographer_partner_profiles.find(params[:id])
  end

  def profile_params
    params.require(:photographer_partner_profile).permit(:notes, tags: [])
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
