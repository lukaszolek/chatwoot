class CampaignParticipant < ApplicationRecord
  belongs_to :outbound_campaign
  belongs_to :account
  belongs_to :participatable, polymorphic: true
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  has_many :llm_decisions, class_name: 'CampaignLlmDecision', dependent: :destroy
  has_many :attribution_events, class_name: 'CampaignAttributionEvent', dependent: :destroy

  validates :current_stage_key, presence: true
  validates :stage_entered_at, presence: true
  validates :outbound_campaign_id,
            uniqueness: { scope: %i[participatable_type participatable_id] }

  scope :due_for_tick, lambda {
    where(paused: false).where('next_action_at <= ?', Time.current)
  }
  scope :in_stage, ->(key) { where(current_stage_key: key) }
end
