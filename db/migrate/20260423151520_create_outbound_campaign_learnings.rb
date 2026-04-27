# Persists insights gleaned from operator interactions with LLM-generated
# drafts: operator regenerated with prompt X (operator_prompt), operator
# manually edited body in way Y (operator_edit), or operator added a free-
# form note (operator_note). Composers consult the most recent N entries
# per slot/locale when building the next prompt, so the system actually
# learns from corrections.
class CreateOutboundCampaignLearnings < ActiveRecord::Migration[7.1]
  def change
    create_table :outbound_campaign_learnings do |t|
      t.references :outbound_campaign, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :draft_message, foreign_key: { to_table: :messages }
      t.string :source_kind, null: false
      t.string :slot
      t.string :locale
      t.text :content, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :outbound_campaign_learnings,
              [:outbound_campaign_id, :active, :created_at],
              name: 'idx_learnings_on_campaign_active_created'
  end
end
