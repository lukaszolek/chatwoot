# == Schema Information
#
# Table name: campaign_knowledge_documents
#
#  id                   :bigint           not null, primary key
#  active               :boolean          default(TRUE), not null
#  content              :text             not null
#  kind                 :string           not null
#  locale               :string
#  position             :integer          default(0), not null
#  title                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  outbound_campaign_id :bigint           not null
#
# Indexes
#
#  idx_knowledge_docs_on_campaign_kind_locale                  (outbound_campaign_id,kind,locale)
#  index_campaign_knowledge_documents_on_outbound_campaign_id  (outbound_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (outbound_campaign_id => outbound_campaigns.id)
#
class CampaignKnowledgeDocument < ApplicationRecord
  belongs_to :outbound_campaign

  KINDS = %w[goal product program_rules faq tone copywriting intro_seed reply_signup open_issues custom].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, presence: true
  validates :content, presence: true

  scope :active_documents, -> { where(active: true) }
end
