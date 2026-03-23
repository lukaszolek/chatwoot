class AddVoucherCurrencyToInfluencerProfiles < ActiveRecord::Migration[7.0]
  def change
    add_column :influencer_profiles, :voucher_currency, :string, default: 'EUR', null: false
  end
end
