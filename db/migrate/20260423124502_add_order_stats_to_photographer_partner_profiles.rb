class AddOrderStatsToPhotographerPartnerProfiles < ActiveRecord::Migration[7.1]
  def change
    change_table :photographer_partner_profiles, bulk: true do |t|
      t.integer  :orders_total, default: 0, null: false
      t.integer  :orders_last_30d, default: 0, null: false
      t.integer  :orders_last_90d, default: 0, null: false
      t.datetime :first_order_completed_at
      t.datetime :last_order_completed_at
      t.datetime :order_stats_refreshed_at
    end
    add_index :photographer_partner_profiles, :last_order_completed_at
    add_index :photographer_partner_profiles, :order_stats_refreshed_at
  end
end
