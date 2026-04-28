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

  def offset
    ((params[:page] || 1).to_i - 1) * PER_PAGE
  end

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
