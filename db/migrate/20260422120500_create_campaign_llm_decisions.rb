class CreateCampaignLlmDecisions < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_llm_decisions do |t|
      t.references :campaign_participant, null: false, foreign_key: { on_delete: :cascade }
      t.references :outbound_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: true, foreign_key: true
      t.bigint :message_id
      t.integer :decision_type, null: false
      t.string :model, null: false
      t.string :prompt_version
      t.string :input_digest
      t.jsonb :output, null: false, default: {}
      t.float :confidence
      t.integer :routed_to
      t.jsonb :token_usage, null: false, default: {}
      t.integer :latency_ms
      t.timestamps
    end

    add_index :campaign_llm_decisions, %i[outbound_campaign_id decision_type created_at],
              name: 'idx_llm_decisions_campaign_type_time'
    add_index :campaign_llm_decisions, :message_id,
              name: 'idx_llm_decisions_message'
  end
end
