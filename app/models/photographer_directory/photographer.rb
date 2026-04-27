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
    alias_method :lock_non_consent_columns!, :lock_non_writable_columns!
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
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::ConnectionBad
  Rails.logger.warn('[outreach] photographer_directory secondary DB unreachable at boot — attr_readonly will be applied on first use')
end
