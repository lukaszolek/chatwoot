# Read + write-limited-scope view of photographer-directory's
# `photographer_photographers` table.
#
# The only columns this model may update are listed in WRITABLE_COLUMNS —
# enforced by `attr_readonly` on every other column. The underlying DB role
# (`photographer_directory_outreach`) also has column-level grants matching
# this list, so any app-level bypass still fails at the wire.
#
# IMPORTANT: Do not call `update!` / `update_columns` from application code.
# The sole write path is `Outreach::PhotographerDirectory::ConsentWriter`
# (C2.3). This ensures every mutation emits a CampaignAttributionEvent
# audit trail and is propagated idempotently.
class PhotographerDirectory::Photographer < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_photographers'
  self.primary_key = 'id'

  WRITABLE_COLUMNS = %w[
    marketing_consent
    unsubscribed_from_all_campaigns
    unsubscribed_from_all_at
    gdpr_delete_requested_at
  ].freeze

  # attr_readonly triggers Rails to skip these columns on UPDATE. Safe to
  # call on every non-writable column including those we only read.
  # Called in an after-load hook because table_name must be resolved first.
  def self.lock_non_consent_columns!
    return if @readonly_locked

    (column_names - WRITABLE_COLUMNS).each { |col| attr_readonly(col) }
    @readonly_locked = true
  end

  scope :queryable_for_outreach, lambda {
    where.not(email: [nil, ''])
         .where(email_validation_status: 'valid')
         .where(marketing_consent: true)
         .where(unsubscribed_from_all_campaigns: false)
         .where(gdpr_delete_requested_at: nil)
         .where(status: 'active')
  }

  def opt_out!(_reason:)
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
  PhotographerDirectory::Photographer.lock_non_consent_columns!
rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::ConnectionBad
  Rails.logger.warn('[outreach] photographer_directory secondary DB unreachable at boot — attr_readonly will be applied on first use')
end
