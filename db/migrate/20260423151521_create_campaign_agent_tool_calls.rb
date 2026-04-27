# Audit log for every Outreach::Agent::Toolbox dispatch. Captures
# parameters the LLM passed, what the tool returned, success/failure, and
# performance. Enables postmortems on agent behavior and detection of
# prompt-injection attempts (e.g. LLM trying to call update_marketing_consent
# with a sender_email that mismatches the conversation scope).
class CreateCampaignAgentToolCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_agent_tool_calls do |t|
      t.references :photographer_partner_profile, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :draft_message, foreign_key: { to_table: :messages }
      t.string :tool_name, null: false
      t.jsonb :params, default: {}, null: false
      t.jsonb :result, default: {}, null: false
      t.boolean :success, default: false, null: false
      t.text :error_message
      t.string :model
      t.integer :latency_ms
      t.timestamps
    end
    add_index :campaign_agent_tool_calls, :tool_name
  end
end
