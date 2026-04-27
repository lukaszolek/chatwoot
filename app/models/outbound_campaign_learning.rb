# Insights captured from operator interactions with LLM-generated drafts.
# Composers consult the most recent N entries (matching slot/locale) when
# building the next prompt, so the system actually adapts to corrections.
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
