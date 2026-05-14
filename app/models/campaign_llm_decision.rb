# == Schema Information
#
# Table name: campaign_llm_decisions
#
#  id                      :bigint           not null, primary key
#  confidence              :float
#  decision_type           :integer          not null
#  input_digest            :string
#  latency_ms              :integer
#  model                   :string           not null
#  output                  :jsonb            not null
#  prompt_version          :string
#  routed_to               :integer
#  token_usage             :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  campaign_participant_id :bigint           not null
#  conversation_id         :bigint
#  message_id              :bigint
#  outbound_campaign_id    :bigint           not null
#
# Indexes
#
#  idx_llm_decisions_campaign_type_time                     (outbound_campaign_id,decision_type,created_at)
#  idx_llm_decisions_message                                (message_id)
#  index_campaign_llm_decisions_on_campaign_participant_id  (campaign_participant_id)
#  index_campaign_llm_decisions_on_conversation_id          (conversation_id)
#  index_campaign_llm_decisions_on_outbound_campaign_id     (outbound_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_participant_id => campaign_participants.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (outbound_campaign_id => outbound_campaigns.id) ON DELETE => cascade
#
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
