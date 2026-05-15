# Insights captured from operator interactions with LLM-generated drafts.
# Composers consult the most recent N entries (matching slot/locale) when
# building the next prompt, so the system actually adapts to corrections.
# == Schema Information
#
# Table name: outbound_campaign_learnings
#
#  id                   :bigint           not null, primary key
#  active               :boolean          default(TRUE), not null
#  content              :text             not null
#  locale               :string
#  slot                 :string
#  source_kind          :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  draft_message_id     :bigint
#  outbound_campaign_id :bigint           not null
#  user_id              :bigint
#
# Indexes
#
#  idx_learnings_on_campaign_active_created                   (outbound_campaign_id,active,created_at)
#  index_outbound_campaign_learnings_on_draft_message_id      (draft_message_id)
#  index_outbound_campaign_learnings_on_outbound_campaign_id  (outbound_campaign_id)
#  index_outbound_campaign_learnings_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (draft_message_id => messages.id)
#  fk_rails_...  (outbound_campaign_id => outbound_campaigns.id)
#  fk_rails_...  (user_id => users.id)
#
class OutboundCampaignLearning < ApplicationRecord
  belongs_to :outbound_campaign
  belongs_to :user, optional: true
  belongs_to :draft_message, class_name: 'Message', optional: true

  SOURCE_KINDS = %w[operator_edit operator_prompt operator_note].freeze

  validates :source_kind, presence: true, inclusion: { in: SOURCE_KINDS }
  validates :content, presence: true

  scope :active_learnings, -> { where(active: true) }
  scope :for_slot, ->(slot) { where('slot IS NULL OR slot = ?', slot) }
  scope :for_locale, ->(locale) { where('locale IS NULL OR locale = ?', locale) }
end
