class CreatePhotographerPartnerProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :photographer_partner_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :email, null: false
      t.string :business_name
      t.string :owner_name
      t.string :website
      t.string :country_code
      t.string :phone
      t.string :instagram_handle
      t.string :preferred_language
      t.boolean :marketing_consent, null: false, default: false
      t.datetime :gdpr_delete_requested_at
      t.string :source_status
      t.integer :partnership_status, null: false, default: 0
      t.datetime :partnership_status_changed_at
      t.string :tags, array: true, default: []
      t.text :notes
      t.datetime :last_synced_at
      t.references :contact, null: true, foreign_key: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :photographer_partner_profiles, %i[account_id external_id], unique: true,
                                                                          name: 'idx_photographer_profiles_account_external'
    add_index :photographer_partner_profiles, %i[account_id email], unique: true,
                                                                    name: 'idx_photographer_profiles_account_email'
    add_index :photographer_partner_profiles, :partnership_status
  end
end
