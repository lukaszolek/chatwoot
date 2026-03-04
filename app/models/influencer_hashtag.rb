class InfluencerHashtag < ApplicationRecord
  belongs_to :account

  validates :tag, presence: true, uniqueness: { scope: %i[account_id language] }
  validates :language, presence: true

  scope :starred, -> { where(starred: true) }
  scope :by_language, ->(lang) { where(language: lang) }
  scope :with_stats, -> { where.not(stats_fetched_at: nil) }
end
