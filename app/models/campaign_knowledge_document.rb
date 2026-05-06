class CampaignKnowledgeDocument < ApplicationRecord
  belongs_to :outbound_campaign

  KINDS = %w[goal product program_rules faq tone copywriting intro_seed reply_signup open_issues custom].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, presence: true
  validates :content, presence: true

  scope :active_documents, -> { where(active: true) }
end
