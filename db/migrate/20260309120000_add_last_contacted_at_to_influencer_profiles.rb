class AddLastContactedAtToInfluencerProfiles < ActiveRecord::Migration[7.0]
  def change
    add_column :influencer_profiles, :last_contacted_at, :datetime
  end
end
