# Per-campaign knowledge base (goal, product, program rules, FAQ, tone,
# open issues). LLM composers consume this via
# OutboundCampaign#knowledge_dump(locale:) when generating emails. Editable
# from UI (Outreach → Knowledge) so operator can iterate without code
# changes.
class CreateCampaignKnowledgeDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_knowledge_documents do |t|
      t.references :outbound_campaign, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :locale
      t.integer :position, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :campaign_knowledge_documents,
              [:outbound_campaign_id, :kind, :locale],
              name: 'idx_knowledge_docs_on_campaign_kind_locale'
  end
end
