class CreateCampaignDrafts < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_drafts do |t|
      t.references :campaign_participant, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: true
      t.references :campaign_llm_decision, null: true, foreign_key: true
      t.string :subject, null: false
      t.text :body, null: false
      t.string :template_slot, null: false
      t.string :locale, null: false
      t.integer :status, null: false, default: 0
      t.references :assigned_user, null: true, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.references :reviewed_by_user, null: true, foreign_key: { to_table: :users }
      t.datetime :send_after_at
      t.integer :iteration_count, null: false, default: 0
      t.timestamps
    end

    add_index :campaign_drafts, %i[status created_at], name: 'idx_campaign_drafts_status_time'
  end
end
