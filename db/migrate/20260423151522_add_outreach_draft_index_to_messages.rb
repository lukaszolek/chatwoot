# Partial index for the "list pending outreach drafts" path
# (Message.pending_outreach_drafts). Without this the listing scans all
# messages every time.
class AddOutreachDraftIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_messages_on_outreach_draft_status
        ON messages
        ((additional_attributes->>'outreach_draft'), (additional_attributes->>'draft_status'))
        WHERE additional_attributes ? 'outreach_draft'
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX IF EXISTS index_messages_on_outreach_draft_status
    SQL
  end
end
