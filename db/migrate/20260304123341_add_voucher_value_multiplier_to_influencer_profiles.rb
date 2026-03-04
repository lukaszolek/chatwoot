class AddVoucherValueMultiplierToInfluencerProfiles < ActiveRecord::Migration[7.0]
  def change
    add_column :influencer_profiles, :voucher_value_multiplier, :decimal, precision: 3, scale: 2, default: 1.0, null: false
  end
end
