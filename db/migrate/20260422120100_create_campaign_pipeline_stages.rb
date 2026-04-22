class CreateCampaignPipelineStages < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_pipeline_stages do |t|
      t.references :outbound_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.integer :position, null: false
      t.integer :on_enter_action, null: false
      t.string :template_slot
      t.integer :auto_advance_after_hours
      t.string :next_stage_key
      t.jsonb :branch_rules, null: false, default: {}
      t.timestamps
    end

    add_index :campaign_pipeline_stages, %i[outbound_campaign_id key], unique: true,
                                                                       name: 'idx_pipeline_stages_campaign_key'
    add_index :campaign_pipeline_stages, %i[outbound_campaign_id position],
              name: 'idx_pipeline_stages_campaign_position'
  end
end
