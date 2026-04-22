class CreateOutboundCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :outbound_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :program_key, null: false
      t.integer :status, null: false, default: 0
      t.references :inbox, null: true, foreign_key: true
      t.references :sender_user, null: true, foreign_key: { to_table: :users }
      t.jsonb :config, null: false, default: {}
      t.jsonb :audience_source_config, null: false, default: {}
      t.timestamps
    end

    add_index :outbound_campaigns, %i[account_id program_key], unique: true,
                                                               name: 'idx_outbound_campaigns_account_program'
    add_index :outbound_campaigns, :status
  end
end
