class CampaignLlmDecision < ApplicationRecord
  belongs_to :campaign_participant
  belongs_to :outbound_campaign
  belongs_to :conversation, optional: true

  enum :decision_type, {
    compose_intro: 0,
    classify_reply: 1,
    draft_reply: 2
  }

  enum :routed_to, {
    auto_send: 0,
    operator_draft: 1,
    escalate: 2
  }, prefix: :routed_to

  validates :model, presence: true
end
