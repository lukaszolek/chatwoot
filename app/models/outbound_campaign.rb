class OutboundCampaign < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :sender_user, class_name: 'User', optional: true

  has_many :pipeline_stages, class_name: 'CampaignPipelineStage', dependent: :destroy
  has_many :participants, class_name: 'CampaignParticipant', dependent: :destroy
  has_many :knowledge_documents, class_name: 'CampaignKnowledgeDocument', dependent: :destroy
  has_many :learnings, class_name: 'OutboundCampaignLearning', dependent: :destroy

  enum :status, { draft: 0, active: 1, paused: 2, archived: 3 }

  validates :name, presence: true
  validates :program_key, presence: true, uniqueness: { scope: :account_id }

  scope :runnable, -> { active }

  # Concatenates all active knowledge documents (globally + matching locale)
  # into a single text block for the LLM composer's system prompt. Filtered
  # by locale: globals (locale=nil) always; locale-specific only when
  # matching the participant's locale.
  def knowledge_dump(locale: nil)
    docs = knowledge_documents
           .where(active: true)
           .where('locale IS NULL OR locale = ?', locale)
           .order(:kind, :position, :id)
    return '(empty)' if docs.empty?

    docs.map { |d| "## #{d.kind.upcase} — #{d.title}#{d.locale ? " [#{d.locale}]" : ''}\n\n#{d.content}" }
        .join("\n\n---\n\n")
  end

  # Recent operator-derived learnings to feed back into composers. Filters
  # by slot (intro/reminder/breakup/reply/nil) and locale (specific or nil).
  def recent_learnings(slot: nil, locale: nil, limit: 20)
    scope = learnings.where(active: true)
    scope = scope.where('slot IS NULL OR slot = ?', slot) if slot
    scope = scope.where('locale IS NULL OR locale = ?', locale) if locale
    scope.order(created_at: :desc).limit(limit)
  end

  def manual_review_mode?
    !!manual_review_mode
  end
end
