class CampaignDraft < ApplicationRecord
  belongs_to :campaign_participant
  belongs_to :conversation
  belongs_to :campaign_llm_decision, optional: true
  belongs_to :assigned_user, class_name: 'User', optional: true
  belongs_to :reviewed_by_user, class_name: 'User', optional: true

  enum :status, {
    pending_review: 0,
    approved: 1,
    rejected: 2,
    sent: 3,
    superseded: 4
  }

  validates :subject, presence: true
  validates :body, presence: true
  validates :template_slot, presence: true
  validates :locale, presence: true

  scope :inbox, -> { pending_review.order(created_at: :asc) }
end
