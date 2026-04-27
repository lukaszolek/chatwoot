# Moves PII (email, business_name, owner_name, website, country_code,
# phone, instagram_handle, preferred_language, marketing_consent,
# source_status, gdpr_delete_requested_at) out of chatwoot's
# photographer_partner_profiles. The canonical row lives in
# photographer_directory.photographer_photographers; chatwoot references
# it by external_id and reads PII through a delegation on the model.
#
# After this migration:
#   - photographer_partner_profiles carries ONLY chatwoot-side outreach
#     state (partnership_status*, marketing_consent_state, notes, tags,
#     metadata, contact_id, external_id, account_id, timestamps).
#   - Any read of .email / .business_name / etc. fans out to the
#     secondary DB via PhotographerDirectory::Photographer.
#   - The unique (account_id, email) index is dropped — uniqueness is
#     enforced upstream in the directory.
class DropCopiedPiiFromPhotographerPartnerProfiles < ActiveRecord::Migration[7.1]
  def up
    remove_index :photographer_partner_profiles, name: 'idx_photographer_profiles_account_email'

    %i[
      email
      business_name
      owner_name
      website
      country_code
      phone
      instagram_handle
      preferred_language
      marketing_consent
      source_status
      gdpr_delete_requested_at
      last_synced_at
    ].each do |col|
      remove_column :photographer_partner_profiles, col if column_exists?(:photographer_partner_profiles, col)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
