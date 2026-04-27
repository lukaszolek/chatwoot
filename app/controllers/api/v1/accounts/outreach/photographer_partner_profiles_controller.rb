class Api::V1::Accounts::Outreach::PhotographerPartnerProfilesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :profile, except: [:index, :create, :facets, :pipeline, :refresh_stats]

  PER_PAGE = 50

  def index
    scope = apply_filters(Current.account.photographer_partner_profiles.order(created_at: :desc))
    @total = scope.count
    @profiles = scope.limit(PER_PAGE).offset(((params[:page] || 1).to_i - 1) * PER_PAGE).to_a
    # Single IN-query to the secondary DB so the jbuilder doesn't hit
    # directory once per row when rendering PII.
    PhotographerPartnerProfile.preload_sources!(@profiles)
  end

  def show
    PhotographerPartnerProfile.preload_sources!([@profile])
  end

  # Manual creation is disabled under SSOT-in-directory: PII lives in
  # photographer-directory, so a photographer must first exist there.
  # The "Add photographer" UI flow instead searches the directory and
  # triggers the import endpoint. Keeping this endpoint as a 422 so the
  # old UI doesn't hard-crash if someone still hits it.
  def create
    render json: {
      error: 'manual_creation_disabled',
      message: 'Photographer records are now owned by photographer-directory. Use directory search + import instead.'
    }, status: :unprocessable_entity
  end

  def update
    pii = pii_params
    chatwoot_state = profile_params

    pii_hash = pii.to_h.transform_keys(&:to_sym)
    chatwoot_hash = chatwoot_state.to_h

    ActiveRecord::Base.transaction do
      # PII first — directory is SSOT. If the writer rejects (grants
      # missing, validation fail), we abort before touching local state.
      if pii_hash.any?
        Outreach::PhotographerDirectory::ProfileWriter
          .new(@profile, user: Current.user)
          .update!(pii_hash)
      end
      @profile.update!(chatwoot_hash) if chatwoot_hash.any?
    end

    PhotographerPartnerProfile.preload_sources!([@profile])
    render :show
  rescue Outreach::PhotographerDirectory::ProfileWriter::ValidationError => e
    render json: { error: 'validation_error', message: e.message }, status: :unprocessable_entity
  rescue Outreach::PhotographerDirectory::ProfileWriter::UniqueConflict => e
    render json: {
      error: 'directory_unique_conflict',
      message: e.message,
      hint: 'Wartość już używa inny fotograf w directory — wybierz inną.'
    }, status: :unprocessable_entity
  rescue Outreach::PhotographerDirectory::ProfileWriter::ForeignKeyMissing => e
    render json: {
      error: 'directory_foreign_key_missing',
      message: e.message,
      hint: 'Domena/encja musi najpierw zostać utworzona w photographer-directory.'
    }, status: :unprocessable_entity
  rescue Outreach::PhotographerDirectory::ProfileWriter::GrantsMissing => e
    render json: {
      error: 'directory_grants_missing',
      message: e.message,
      hint: 'Run db/photographer_directory_grants/2026-04-25-pii-update-grants.sql against the photographer_directory DB.'
    }, status: :unprocessable_entity
  rescue Outreach::PhotographerDirectory::ProfileWriter::PhotographerNotFound => e
    render json: { error: 'directory_row_missing', message: e.message }, status: :not_found
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
    PhotographerPartnerProfile.preload_sources!([@profile])
    render :show
  end

  # Distinct country_code + preferred_language values across the full
  # photographer-directory DB — the operator searches the entire
  # directory from this screen, so autocomplete should cover every
  # country/locale present there.
  def facets
    scope = PhotographerDirectory::Photographer
    country_codes = scope.where.not(country_code: [nil, '']).distinct.pluck(:country_code)
    locales = scope.where.not(preferred_language: [nil, '']).distinct.pluck(:preferred_language)
    render json: {
      country_codes: country_codes.map { |c| c.to_s.upcase }.uniq.sort,
      locales: locales.map(&:to_s).uniq.sort
    }
  end

  def pipeline
    scope = Current.account.photographer_partner_profiles.active_outreach
    profiles = scope.to_a
    PhotographerPartnerProfile.preload_sources!(profiles)
    grouped = PhotographerPartnerProfile::PIPELINE_STAGES.index_with { |_| [] }
    last_refreshed_at = nil
    profiles.each do |profile|
      stage = profile.pipeline_stage
      next unless stage

      grouped[stage] << profile
      ts = profile.order_stats_refreshed_at
      last_refreshed_at = ts if ts && (last_refreshed_at.nil? || ts > last_refreshed_at)
    end
    @pipeline_stages = grouped
    @stats_refreshed_at = last_refreshed_at
  end

  def refresh_stats
    result = Outreach::OrderStats::Fetcher.new(account: Current.account).perform
    render json: { result: result.to_h }, status: :ok
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
    PhotographerPartnerProfile.preload_sources!([@profile])
    render :show
  end

  private

  # PII filters (q / country_code / locale) are resolved against the
  # directory first; we then narrow the local profiles by the matching
  # external_ids. Status filter stays local (it's chatwoot-side).
  def apply_filters(scope)
    scope = scope.where(partnership_status: params[:status]) if params[:status].present?

    needs_directory_filter = params[:country_code].present? ||
                             params[:locale].present? ||
                             params[:q].present?
    if needs_directory_filter
      directory_ids = filter_directory_ids
      return scope.none if directory_ids.empty?

      scope = scope.where(external_id: directory_ids)
    end

    scope
  end

  def filter_directory_ids
    dscope = PhotographerDirectory::Photographer
    dscope = dscope.where(country_code: params[:country_code].to_s.downcase) if params[:country_code].present?
    dscope = dscope.where(preferred_language: params[:locale]) if params[:locale].present?
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      dscope = dscope.where(
        'email ILIKE :q OR business_name ILIKE :q OR owner_name ILIKE :q OR instagram_handle ILIKE :q', q: q
      )
    end
    dscope.pluck(:id).map(&:to_s)
  end

  def profile
    @profile ||= Current.account.photographer_partner_profiles.find(params[:id])
  end

  # Chatwoot-side outreach state — owned locally, written by AR.
  def profile_params
    params.require(:photographer_partner_profile).permit(
      :notes, :marketing_consent_state, :partnership_status, tags: []
    )
  end

  # PII fields — SSOT lives in photographer-directory, written via
  # ProfileWriter (which validates + audits). The .permit().to_h call
  # returns only keys present in the request, so missing fields are not
  # pushed to the writer. Operator-supplied empty strings are forwarded
  # so a deliberate clear ("remove instagram handle") propagates through;
  # the writer turns blanks into nil.
  def pii_params
    params.require(:photographer_partner_profile).permit(
      :email, :business_name, :owner_name, :website, :country_code,
      :instagram_handle, :phone, :native_language, :preferred_language
    ).to_h
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
