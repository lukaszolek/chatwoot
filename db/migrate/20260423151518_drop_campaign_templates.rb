# Drops static per-locale outbound copy. Replaced by LLM composers that
# generate every email (intro / reminder / breakup / reply) from the
# campaign knowledge base + conversation history + recent operator
# learnings.
class DropCampaignTemplates < ActiveRecord::Migration[7.1]
  def up
    drop_table :campaign_templates
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
