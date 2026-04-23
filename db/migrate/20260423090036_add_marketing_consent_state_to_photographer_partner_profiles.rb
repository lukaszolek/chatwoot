# Adds a tri-state consent column: unknown (0, default), granted (1),
# declined (2). The existing boolean `marketing_consent` stays for
# interop with photographer-directory's schema (source of truth), but
# chatwoot UI operators now work with the tri-state so the uncertain
# middle (silence — neither yes nor no) is explicit.
class AddMarketingConsentStateToPhotographerPartnerProfiles < ActiveRecord::Migration[7.1]
  def up
    add_column :photographer_partner_profiles, :marketing_consent_state,
               :integer, default: 0, null: false
    add_index :photographer_partner_profiles, :marketing_consent_state

    # Backfill from existing flags:
    #   partnership_status = do_not_contact (7) → declined (2)
    #   marketing_consent = true                → granted (1)
    #   otherwise                               → unknown (0, default)
    execute <<~SQL.squish
      UPDATE photographer_partner_profiles
         SET marketing_consent_state = 2
       WHERE partnership_status = 7
    SQL
    execute <<~SQL.squish
      UPDATE photographer_partner_profiles
         SET marketing_consent_state = 1
       WHERE partnership_status != 7
         AND marketing_consent = TRUE
    SQL
  end

  def down
    remove_index :photographer_partner_profiles, :marketing_consent_state
    remove_column :photographer_partner_profiles, :marketing_consent_state
  end
end
