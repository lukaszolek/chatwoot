class AddPreselectedStatusToInfluencerProfiles < ActiveRecord::Migration[7.0]
  # Documents the addition of `preselected: 1` to the InfluencerProfile status
  # enum. The column is an integer so no schema change is needed — the enum
  # mapping in the model is authoritative.
  def change
    # no-op: integer enum, value 1 was unused
  end
end
