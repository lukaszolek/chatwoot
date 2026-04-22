class CreateCampaignTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_templates do |t|
      t.references :outbound_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.string :slot, null: false
      t.string :locale, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.text :llm_guidance
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :campaign_templates, %i[outbound_campaign_id slot locale],
              unique: true,
              where: 'active = true',
              name: 'idx_campaign_templates_active_slot_locale'
    add_index :campaign_templates, %i[outbound_campaign_id slot locale active],
              name: 'idx_campaign_templates_slot_locale_active'
  end
end
