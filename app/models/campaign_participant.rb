# == Schema Information
#
# Table name: campaign_participants
#
#  id                   :bigint           not null, primary key
#  current_stage_key    :string           not null
#  last_inbound_at      :datetime
#  last_outbound_at     :datetime
#  metadata             :jsonb            not null
#  next_action_at       :datetime
#  participatable_type  :string           not null
#  paused               :boolean          default(FALSE), not null
#  stage_entered_at     :datetime         not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint
#  conversation_id      :bigint
#  outbound_campaign_id :bigint           not null
#  participatable_id    :bigint           not null
#
# Indexes
#
#  idx_campaign_participants_tick_scan                  (outbound_campaign_id,current_stage_key,next_action_at)
#  idx_campaign_participants_unique_per_campaign        (outbound_campaign_id,participatable_type,participatable_id) UNIQUE
#  index_campaign_participants_on_account_id            (account_id)
#  index_campaign_participants_on_contact_id            (contact_id)
#  index_campaign_participants_on_conversation_id       (conversation_id)
#  index_campaign_participants_on_outbound_campaign_id  (outbound_campaign_id)
#  index_campaign_participants_on_participatable        (participatable_type,participatable_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (outbound_campaign_id => outbound_campaigns.id) ON DELETE => cascade
#
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
