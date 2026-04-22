class Api::V1::Accounts::Outreach::PhotographerPartnerProfilesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :profile, except: [:index, :create]

  PER_PAGE = 50

  def index
    scope = apply_filters(Current.account.photographer_partner_profiles.order(created_at: :desc))
    @total = scope.count
    @profiles = scope.limit(PER_PAGE).offset(((params[:page] || 1).to_i - 1) * PER_PAGE)
  end

  def show; end

  # POST — creates a PhotographerPartnerProfile AND enrolls it in the
  # `photographer_partnership` campaign as a CampaignParticipant at the
  # intro stage (due immediately). Used by the "Add photographer" UI
  # flow for manual/test enrollment when the directory importer has
  # excluded someone (e.g., already onboarding, or a synthetic lead).
  def create
    @profile = Current.account.photographer_partner_profiles.new(create_params)
    @profile.partnership_status = :imported
    ActiveRecord::Base.transaction do
      @profile.save!
      enroll_in_partnership_campaign!(@profile, enrol_params[:enroll] != false)
    end
    render :show, status: :created
  end

  def update
    @profile.update!(profile_params)
    render :show
  end

  def enroll
    campaign = find_partnership_campaign!
    participant = CampaignParticipant.find_or_create_by!(
      outbound_campaign: campaign, account: Current.account, participatable: @profile
    ) do |p|
      p.current_stage_key = 'intro'
      p.stage_entered_at = Time.current
      p.next_action_at = Time.current
    end
    participant.update!(paused: false, next_action_at: Time.current) if participant.paused?
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

  def create_params
    params.require(:photographer_partner_profile).permit(
      :email, :business_name, :owner_name, :website, :country_code,
      :preferred_language, :instagram_handle, :external_id, :notes
    ).tap do |attrs|
      attrs[:external_id] = "manual-#{SecureRandom.hex(6)}" if attrs[:external_id].blank?
      attrs[:marketing_consent] = true
    end
  end

  def enrol_params
    params.permit(:enroll)
  end

  def enroll_in_partnership_campaign!(profile, should_enroll)
    return unless should_enroll

    campaign = find_partnership_campaign!
    CampaignParticipant.create!(
      outbound_campaign: campaign, account: Current.account, participatable: profile,
      current_stage_key: 'intro', stage_entered_at: Time.current, next_action_at: Time.current
    )
  end

  def find_partnership_campaign!
    campaign = Current.account.outbound_campaigns.find_by(program_key: 'photographer_partnership')
    raise ActiveRecord::RecordNotFound, 'photographer_partnership campaign not found — run rake outreach:blueprints:apply' unless campaign

    campaign
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
