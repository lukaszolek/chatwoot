# Shared scope-builder for photographer-directory search.
# Used by:
#   - DirectoryController#search (browses the full directory)
#   - PhotographerPartnerProfilesController#filter_directory_ids
#     (narrows local profiles by directory PII / specialty / rating)
#
# Inputs: an ActiveRecord scope on PhotographerDirectory::Photographer
# and an ActionController::Parameters-like hash of filter values.
# Returns a scope with the requested clauses applied.
module Outreach::PhotographerDirectory::SearchFilters
  module_function

  def apply(scope, params)
    scope = filter_text_query(scope, params[:q])
    scope = scope.where(country_code: params[:country_code].to_s.downcase) if params[:country_code].present?
    scope = scope.where(preferred_language: params[:locale]) if params[:locale].present?
    scope = scope.where('google_rating >= ?', params[:min_rating].to_f) if params[:min_rating].present?
    filter_by_category(scope, params[:category])
  end

  def filter_text_query(scope, q_param)
    return scope if q_param.blank?

    q = "%#{ActiveRecord::Base.sanitize_sql_like(q_param)}%"
    scope.where(
      'email ILIKE :q OR business_name ILIKE :q OR owner_name ILIKE :q OR instagram_handle ILIKE :q',
      q: q
    )
  end

  def filter_by_category(scope, category)
    return scope if category.blank?

    scope.where(
      'EXISTS (SELECT 1 FROM photographer_services s ' \
      'WHERE s.photographer_id = photographer_photographers.id AND s.category = ?)',
      category.to_s
    )
  end
end
