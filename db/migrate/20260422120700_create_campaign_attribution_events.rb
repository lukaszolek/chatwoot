class CreateCampaignAttributionEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_attribution_events do |t|
      t.references :campaign_participant, null: false, foreign_key: { on_delete: :cascade }
      t.integer :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :campaign_attribution_events, %i[campaign_participant_id event_type occurred_at],
              name: 'idx_attribution_events_participant_type_time'
  end
end
