class OutboundCampaign < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :sender_user, class_name: 'User', optional: true

  has_many :pipeline_stages, class_name: 'CampaignPipelineStage', dependent: :destroy
  has_many :templates, class_name: 'CampaignTemplate', dependent: :destroy
  has_many :participants, class_name: 'CampaignParticipant', dependent: :destroy

  enum :status, { draft: 0, active: 1, paused: 2, archived: 3 }

  validates :name, presence: true
  validates :program_key, presence: true, uniqueness: { scope: :account_id }

  scope :runnable, -> { active }
end
