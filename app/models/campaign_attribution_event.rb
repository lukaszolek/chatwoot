# == Schema Information
#
# Table name: campaign_attribution_events
#
#  id                      :bigint           not null, primary key
#  event_type              :integer          not null
#  occurred_at             :datetime         not null
#  payload                 :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  campaign_participant_id :bigint           not null
#
# Indexes
#
#  idx_attribution_events_participant_type_time                  (campaign_participant_id,event_type,occurred_at)
#  index_campaign_attribution_events_on_campaign_participant_id  (campaign_participant_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_participant_id => campaign_participants.id) ON DELETE => cascade
#
class CampaignAttributionEvent < ApplicationRecord
  belongs_to :campaign_participant

  enum :event_type, {
    partnership_signup: 0,
    unsubscribe: 1,
    email_bounce: 2,
    gdpr_delete: 3,
    consent_drift_detected: 4,
    profile_edit: 5
  }, prefix: :event

  validates :occurred_at, presence: true
end
