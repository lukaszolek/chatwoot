# Read + write-limited-scope view of photographer-directory's
# `photographer_photographers` table.
#
# Two layers of write protection:
#   1. App-level — `attr_readonly` on every column NOT in WRITABLE_COLUMNS.
#   2. DB-level — column UPDATE grants on the `photographer_directory_outreach`
#      role (see db/photographer_directory_grants/*.sql). DB grants are the
#      source of truth; the app whitelist mirrors them so writes fail fast
#      at the model layer instead of at the wire.
#
# WRITABLE_COLUMNS contains TWO bands:
#   - Consent / unsubscribe / GDPR (the original 4): written by ConsentWriter
#     in response to inbound replies and operator opt-out actions.
#   - PII fields (email, business_name, owner_name, etc.): written by
#     ProfileWriter when an operator edits the photographer through the
#     chatwoot edit-sidebar. SSOT-in-directory means chatwoot does not keep
#     copies — every edit goes here.
#
# IMPORTANT: Do not call `update!` / `update_columns` directly from
# application code. The two write paths are
# `Outreach::PhotographerDirectory::ConsentWriter` and
# `Outreach::PhotographerDirectory::ProfileWriter`. Both emit audit trails
# (CampaignAttributionEvent) so every mutation is traceable.
# == Schema Information
#
# Table name: photographer_photographers
#
#  id                                                                           :bigint           not null, primary key
#  address                                                                      :text
#  address_verification_result                                                  :jsonb
#  address_verification_status                                                  :enum             default("unverified"), not null
#  address_verified_at                                                          :datetime
#  address_verified_formatted                                                   :text
#  address_verified_lat                                                         :decimal(10, 8)
#  address_verified_lng                                                         :decimal(11, 8)
#  auto_classification_confidence                                               :decimal(5, 2)
#  build_priority                                                               :integer          default(0)
#  business_name                                                                :text             not null
#  country_code                                                                 :text
#  crawl_success                                                                :boolean          default(TRUE)
#  edit_token                                                                   :uuid
#  email                                                                        :text
#  email_obtained_by_us                                                         :boolean          default(FALSE)
#  email_validated_at                                                           :datetime
#  email_validation_status                                                      :enum             default("unknown")
#  established_year                                                             :integer
#  facebook_url                                                                 :text
#  gdpr_delete_requested_at                                                     :timestamptz
#  google_business_name                                                         :text
#  google_photos_count                                                          :integer
#  google_price_level                                                           :integer
#  google_rating                                                                :decimal(2, 1)
#  google_review_count                                                          :integer
#  instagram_bio                                                                :text
#  instagram_external_url                                                       :text
#  instagram_followers                                                          :integer
#  instagram_following                                                          :integer
#  instagram_handle                                                             :text
#  instagram_is_private                                                         :boolean
#  instagram_last_sync_error                                                    :text
#  instagram_last_sync_status                                                   :text
#  instagram_last_synced_at                                                     :datetime
#  instagram_posts_count                                                        :integer
#  instagram_verified                                                           :boolean
#  is_premium                                                                   :boolean          default(FALSE)
#  last_crawled_at                                                              :datetime
#  last_google_sync                                                             :datetime
#  last_viewed_at                                                               :datetime
#  latitude                                                                     :decimal(10, 8)
#  letter_exports                                                               :jsonb
#  linkedin_url                                                                 :text
#  longitude                                                                    :decimal(11, 8)
#  marketing_consent                                                            :boolean          default(FALSE)
#  markets                                                                      :text             is an Array
#  native_language                                                              :text             default("pl")
#  owner_name                                                                   :text
#  phone                                                                        :text
#  pinterest_url                                                                :text
#  preferred_language(Preferred language for edit interface (de, en, pl, etc.)) :text             default("de")
#  profile_image_url                                                            :text
#  public_email                                                                 :text
#  public_phone                                                                 :text
#  service_radius                                                               :integer
#  slug                                                                         :text             not null
#  status                                                                       :enum             default("pending"), not null
#  structured_contact                                                           :jsonb
#  terms_accepted                                                               :boolean          default(FALSE)
#  terms_accepted_at                                                            :datetime
#  unsubscribed_all_until                                                       :timestamptz
#  unsubscribed_from_all_at                                                     :timestamptz
#  unsubscribed_from_all_campaigns                                              :boolean          default(FALSE)
#  verified_at                                                                  :datetime
#  view_count                                                                   :integer          default(0)
#  website                                                                      :text             not null
#  welcome_email_requested                                                      :boolean          default(FALSE), not null
#  welcome_email_sent_at                                                        :datetime
#  whatsapp_available                                                           :boolean          default(FALSE)
#  years_of_experience                                                          :integer
#  created_at                                                                   :datetime         not null
#  updated_at                                                                   :datetime         not null
#  city_id                                                                      :bigint
#  external_id                                                                  :text
#  google_place_id                                                              :text
#
# Indexes
#
#  photographer_address_verification_idx              (address_verification_status)
#  photographer_country_idx                           (country_code)
#  photographer_email_validation_idx                  (email_validation_status)
#  photographer_geo_idx                               (latitude,longitude)
#  photographer_google_place_idx                      (google_place_id)
#  photographer_location_idx                          (city_id)
#  photographer_pending_city_review_idx               (status,created_at) WHERE (status = 'pending_city_review'::photographer_status)
#  photographer_photographers_google_place_id_unique  (google_place_id) UNIQUE
#  photographer_photographers_slug_unique             (slug) UNIQUE
#  photographer_photographers_website_unique          (website) UNIQUE
#  photographer_priority_idx                          (build_priority)
#  photographer_slug_idx                              (slug)
#  photographer_status_idx                            (status)
#
# Foreign Keys
#
#  photographer_photographers_website_websites_domain_fk  (website => websites.domain)
#
class PhotographerDirectory::Photographer < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_photographers'
  self.primary_key = 'id'

  CONSENT_WRITABLE_COLUMNS = %w[
    marketing_consent
    unsubscribed_from_all_campaigns
    unsubscribed_from_all_at
    gdpr_delete_requested_at
  ].freeze

  PII_WRITABLE_COLUMNS = %w[
    email
    business_name
    owner_name
    website
    country_code
    instagram_handle
    phone
    native_language
    preferred_language
  ].freeze

  WRITABLE_COLUMNS = (CONSENT_WRITABLE_COLUMNS + PII_WRITABLE_COLUMNS).freeze

  # attr_readonly triggers Rails to skip these columns on UPDATE. Safe to
  # call on every non-writable column including those we only read.
  # Called in an after-load hook because table_name must be resolved first.
  def self.lock_non_writable_columns!
    return if @readonly_locked

    (column_names - WRITABLE_COLUMNS).each { |col| attr_readonly(col) }
    @readonly_locked = true
  end

  # Backward-compat alias — kept so anything that referenced the old name
  # keeps working until callers migrate.
  class << self
    alias lock_non_consent_columns! lock_non_writable_columns!
  end

  scope :queryable_for_outreach, lambda {
    where.not(email: [nil, ''])
         .where(email_validation_status: 'valid')
         .where(marketing_consent: true)
         .where(unsubscribed_from_all_campaigns: false)
         .where(gdpr_delete_requested_at: nil)
         .where(status: 'active')
  }

  # Reason is tracked by the caller (ConsentWriter → CampaignAttributionEvent),
  # not stored on the source row.
  def opt_out!
    update!(marketing_consent: false, unsubscribed_from_all_campaigns: true,
            unsubscribed_from_all_at: Time.current)
  end

  def request_gdpr_delete!
    update!(gdpr_delete_requested_at: Time.current)
  end
end

# Lock the readonly attributes at boot-time (once the secondary DB connection
# is reachable and columns are introspected). Guarded so specs and rake tasks
# can disable the secondary without crashing boot.
Rails.application.config.after_initialize do
  PhotographerDirectory::Photographer.lock_non_writable_columns!
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::ConnectionBad
  # Reachable-but-not-migrated (e.g. CI/FOSS, where the secondary points at the
  # primary db and the photographer_* tables do not exist) raises StatementInvalid.
  Rails.logger.warn('[outreach] photographer_directory secondary DB unavailable at boot — attr_readonly will be applied on first use')
end
