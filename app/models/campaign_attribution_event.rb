class CampaignAttributionEvent < ApplicationRecord
  belongs_to :campaign_participant

  enum :event_type, {
    partnership_signup: 0,
    unsubscribe: 1,
    email_bounce: 2,
    gdpr_delete: 3,
    consent_drift_detected: 4
  }, prefix: :event

  validates :occurred_at, presence: true
end
