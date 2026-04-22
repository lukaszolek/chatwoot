class CreateCampaignParticipants < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_participants do |t|
      t.references :outbound_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: true
      t.references :participatable, polymorphic: true, null: false
      t.string :current_stage_key, null: false
      t.datetime :stage_entered_at, null: false
      t.datetime :next_action_at
      t.datetime :last_outbound_at
      t.datetime :last_inbound_at
      t.references :conversation, null: true, foreign_key: true
      t.references :contact, null: true, foreign_key: true
      t.jsonb :metadata, null: false, default: {}
      t.boolean :paused, null: false, default: false
      t.timestamps
    end

    add_index :campaign_participants,
              %i[outbound_campaign_id participatable_type participatable_id],
              unique: true,
              name: 'idx_campaign_participants_unique_per_campaign'
    add_index :campaign_participants,
              %i[outbound_campaign_id current_stage_key next_action_at],
              name: 'idx_campaign_participants_tick_scan'
  end
end
