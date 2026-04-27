class AddManualReviewModeToOutboundCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :outbound_campaigns, :manual_review_mode, :boolean, default: true, null: false
  end
end
