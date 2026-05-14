# Read-only window into photographer-directory's `photographer_services`
# table. Used by the outreach search UI to filter photographers by what
# they shoot (wedding, maternity, family, …). The chatwoot role has
# SELECT only — see db/photographer_directory_grants/2026-04-28-services-select-grant.sql.
# == Schema Information
#
# Table name: photographer_services
#
#  id                                                                                                    :bigint           not null, primary key
#  category                                                                                              :text             not null
#  content_slug(Unique slug for linking translations (format: service-{category}-{subcategory}-{index})) :text
#  display_order                                                                                         :integer          default(0)
#  includes_partner                                                                                      :boolean          default(TRUE)
#  includes_siblings                                                                                     :boolean          default(TRUE)
#  is_highlighted                                                                                        :boolean          default(FALSE)
#  is_primary                                                                                            :boolean          default(TRUE)
#  language                                                                                              :text             not null
#  max_people                                                                                            :integer
#  meta_description                                                                                      :text
#  meta_title                                                                                            :text
#  optimal_timeframe                                                                                     :text
#  service_description                                                                                   :text
#  service_name                                                                                          :text             not null
#  service_slug                                                                                          :text
#  session_duration                                                                                      :text
#  subcategory                                                                                           :text
#  created_at                                                                                            :datetime
#  photographer_id                                                                                       :bigint           not null
#
# Indexes
#
#  photographer_services_photographer_language_idx  (photographer_id,language)
#  service_category_idx                             (category)
#  service_photographer_idx                         (photographer_id)
#  service_primary_idx                              (is_primary)
#  service_slug_idx                                 (service_slug)
#  service_subcategory_idx                          (subcategory)
#  services_content_slug_idx                        (content_slug)
#  services_unique_content_idx                      (photographer_id,content_slug,language) UNIQUE WHERE (content_slug IS NOT NULL)
#
class PhotographerDirectory::Service < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_services'
  self.primary_key = 'id'
end
