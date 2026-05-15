# == Schema Information
#
# Table name: influencer_hashtags
#
#  id               :bigint           not null, primary key
#  apify_stats      :jsonb
#  language         :string           not null
#  posts_count      :integer
#  profiles_count   :integer          default(1)
#  starred          :boolean          default(FALSE)
#  stats_fetched_at :datetime
#  tag              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  idx_hashtags_account_tag_lang            (account_id,tag,language) UNIQUE
#  idx_hashtags_lang_starred                (account_id,language,starred)
#  index_influencer_hashtags_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class InfluencerHashtag < ApplicationRecord
  belongs_to :account

  validates :tag, presence: true, uniqueness: { scope: %i[account_id language] }
  validates :language, presence: true

  scope :starred, -> { where(starred: true) }
  scope :by_language, ->(lang) { where(language: lang) }
  scope :with_stats, -> { where.not(stats_fetched_at: nil) }
end
