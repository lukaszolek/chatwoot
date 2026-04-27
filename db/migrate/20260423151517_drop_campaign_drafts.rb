# Drops the standalone CampaignDraft model. Outreach drafts now live as
# Message rows inside the conversation thread (private: true,
# additional_attributes['outreach_draft'] = true), so an operator reviews
# them in the inbox where the conversation already lives.
class DropCampaignDrafts < ActiveRecord::Migration[7.1]
  def up
    drop_table :campaign_drafts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
