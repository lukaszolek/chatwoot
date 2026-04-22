# Search + import surface over the photographer-directory secondary DB.
# Read-only search that applies `queryable_for_outreach` + optional text
# search on email/business_name/owner_name/instagram_handle. Excludes
# photographer-directory rows already enrolled in another active
# directory campaign (Option C) so we never double-contact active
# onboarding leads.
#
# Import endpoint delegates to Outreach::Enrollment::EnrollFromDirectory
# which upserts profile + contact + campaign participant in a single
# transaction per row.
class Api::V1::Accounts::Outreach::DirectoryController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  PER_PAGE = 30

  def search
    scope = apply_search_filters(
      PhotographerDirectory::Photographer
        .queryable_for_outreach
        .where.not(id: exclusion_ids)
    )
    @total = scope.count
    @results = scope.order(:business_name).limit(PER_PAGE).offset(offset)
    @enrolled_ids = Current.account.photographer_partner_profiles
                           .where(external_id: @results.map { |r| r.id.to_s })
                           .pluck(:external_id)
  end

  def import
    ids = Array(params[:directory_ids])
    return head(:bad_request) if ids.empty?

    result = Outreach::Enrollment::EnrollFromDirectory.new(
      account: Current.account, directory_ids: ids
    ).perform
    render json: { result: result.to_h }, status: :ok
  end

  private

  def apply_search_filters(scope)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where(
        'email ILIKE :q OR business_name ILIKE :q OR owner_name ILIKE :q OR instagram_handle ILIKE :q',
        q: q
      )
    end
    scope = scope.where(country_code: params[:country_code].to_s.downcase) if params[:country_code].present?
    scope = scope.where(preferred_language: params[:locale]) if params[:locale].present?
    scope
  end

  def exclusion_ids
    PhotographerDirectory::CampaignStatus.active_enrolment.select(:photographer_id)
  end

  def offset
    ((params[:page] || 1).to_i - 1) * PER_PAGE
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
