# Search + import surface over the photographer-directory secondary DB.
#
# The UI lets an operator browse the entire directory (not just the
# narrow `queryable_for_outreach` set the cron importer uses). That
# way the operator can find anyone by name / IG / country and decide
# themselves — but we still flag each row with badges so they see:
#
#   - already_enrolled         → we already have a partnership profile
#   - in_directory_campaign    → Option C: in another onboarding CRM
#   - no_marketing_consent     → hasn't opted-in for marketing mail
#   - email_invalid            → email not yet validated or bounced
#
# Base filter: has email, status=active, not unsubscribed, no GDPR
# delete request. Everything else is informational.
class Api::V1::Accounts::Outreach::DirectoryController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  PER_PAGE = 30
  MAX_BULK_IMPORT = 400
  SUPPORTED_LOCALES = %w[pl en de nl fr].freeze

  def search
    scope = apply_search_filters(base_scope)
    @total = scope.count
    @results = scope.order(:business_name).limit(PER_PAGE).offset(offset)

    ids = @results.map(&:id)
    @enrolled_ids = Current.account.photographer_partner_profiles
                           .where(external_id: ids.map(&:to_s))
                           .pluck(:external_id).to_set
    @in_directory_campaign_ids = PhotographerDirectory::CampaignStatus
                                 .active_enrolment
                                 .where(photographer_id: ids)
                                 .pluck(:photographer_id).to_set
  end

  def import
    ids = Array(params[:directory_ids])
    return head(:bad_request) if ids.empty?

    result = Outreach::Enrollment::EnrollFromDirectory.new(
      account: Current.account, directory_ids: ids
    ).perform
    render json: { result: result.to_h }, status: :ok
  end

  def import_filtered
    limit = bulk_import_limit
    scope = bulk_import_scope.limit(limit)
    ids = scope.pluck(:id)
    return render json: { result: empty_bulk_result(limit) }, status: :ok if ids.empty?

    result = Outreach::Enrollment::EnrollFromDirectory.new(
      account: Current.account, directory_ids: ids
    ).perform
    render json: { result: result.to_h.merge(requested: limit, selected: ids.size) }, status: :ok
  end

  def update
    photographer = base_scope.find(params[:id])
    locale = params[:preferred_language].to_s.downcase.presence
    return render json: { error: 'Unsupported locale' }, status: :unprocessable_entity unless SUPPORTED_LOCALES.include?(locale)

    photographer.update!(
      preferred_language: locale,
      native_language: locale
    )

    render json: directory_row_payload(photographer), status: :ok
  end

  private

  def base_scope
    PhotographerDirectory::Photographer
      .where.not(email: [nil, ''])
      .where(status: 'active')
      .where(unsubscribed_from_all_campaigns: false)
      .where(gdpr_delete_requested_at: nil)
  end

  def apply_search_filters(scope)
    Outreach::PhotographerDirectory::SearchFilters.apply(scope, params)
  end

  def bulk_import_scope
    apply_search_filters(base_scope)
      .where.not(id: enrolled_directory_ids)
      .where.not(id: PhotographerDirectory::CampaignStatus.active_enrolment.select(:photographer_id))
      .where("email_validation_status IS NULL OR email_validation_status::text NOT LIKE 'invalid%'")
      .order(:business_name, :id)
  end

  def enrolled_directory_ids
    Current.account.photographer_partner_profiles
           .where.not(external_id: [nil, ''])
           .pluck(:external_id)
           .map(&:to_i)
  end

  def bulk_import_limit
    requested = params[:limit].to_i
    requested = PER_PAGE unless requested.positive?
    [requested, MAX_BULK_IMPORT].min
  end

  def empty_bulk_result(limit)
    {
      requested: limit,
      selected: 0,
      enrolled: 0,
      re_enrolled: 0,
      already_enrolled: 0,
      skipped_dnc: 0,
      skipped_duplicate_email: 0,
      failed: 0,
      errors: []
    }
  end

  def offset
    ((params[:page] || 1).to_i - 1) * PER_PAGE
  end

  def directory_row_payload(row)
    {
      id: row.id,
      email: row.email,
      business_name: row.business_name,
      owner_name: row.owner_name,
      website: row.website,
      country_code: row.country_code&.upcase,
      preferred_language: row.preferred_language,
      instagram_handle: row.instagram_handle,
      marketing_consent: row.marketing_consent,
      email_validation_status: row.email_validation_status,
      google_rating: row.google_rating,
      google_review_count: row.google_review_count,
      already_enrolled: Current.account.photographer_partner_profiles.exists?(external_id: row.id.to_s),
      in_directory_campaign: PhotographerDirectory::CampaignStatus.active_enrolment.exists?(photographer_id: row.id)
    }
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
