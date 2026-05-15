# == Schema Information
#
# Table name: influencer_profiles
#
#  id                         :bigint           not null, primary key
#  apify_data                 :jsonb
#  apify_enriched_at          :datetime
#  apify_error                :string
#  apify_status               :integer          default("apify_none"), not null
#  audience_ages              :jsonb
#  audience_brand_affinity    :jsonb
#  audience_credibility       :float
#  audience_credibility_class :string
#  audience_genders           :jsonb
#  audience_geo               :jsonb
#  audience_interests         :jsonb
#  audience_reachability      :float
#  audience_types             :jsonb
#  avg_comments               :float
#  avg_likes                  :float
#  avg_reel_views             :float
#  avg_saves                  :float
#  avg_shares                 :float
#  bio                        :text
#  effective_er               :float
#  engagement_rate            :float
#  enrichment_pending         :boolean          default(FALSE), not null
#  follower_growth_rate       :float
#  followers_count            :integer
#  following_count            :integer
#  fqs_breakdown              :jsonb
#  fqs_hard_filter_results    :jsonb
#  fqs_score                  :integer
#  fqs_stage1_score           :integer
#  fqs_stage2_score           :integer
#  fullname                   :string
#  hidden_like_posts_rate     :float
#  interests                  :jsonb
#  is_verified                :boolean          default(FALSE)
#  last_contacted_at          :datetime
#  last_post_at               :datetime
#  last_synced_at             :datetime
#  lock_version               :integer          default(0)
#  median_reel_views          :float
#  paid_post_performance      :float
#  platform                   :string           default("instagram"), not null
#  posts_count                :integer
#  profile_picture_url        :text
#  profile_url                :text
#  raw_report_data            :jsonb
#  recent_posts               :jsonb
#  recent_reels               :jsonb
#  rejection_reason           :string
#  report_fetched_at          :datetime
#  search_engagement_rate     :float
#  stat_history               :jsonb
#  status                     :integer          default("discovered")
#  target_market              :string
#  top_hashtags               :jsonb
#  username                   :string           not null
#  voucher_currency           :string           default("EUR"), not null
#  voucher_value_multiplier   :decimal(3, 2)    default(1.0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  contact_id                 :bigint           not null
#  external_report_id         :string
#  external_search_id         :string
#
# Indexes
#
#  idx_influencer_profiles_account_username_platform      (account_id,username,platform) UNIQUE
#  index_influencer_profiles_on_account_id                (account_id)
#  index_influencer_profiles_on_account_id_and_fqs_score  (account_id,fqs_score)
#  index_influencer_profiles_on_account_id_and_status     (account_id,status)
#  index_influencer_profiles_on_contact_id                (contact_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#
class InfluencerProfile < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  VALID_TRANSITIONS = {
    discovered: %i[preselected enriched rejected],
    preselected: %i[enriched rejected],
    enriched: %i[approved rejected],
    approved: %i[contacted confirmed rejected],
    rejected: %i[discovered],
    contacted: %i[confirmed declined],
    confirmed: %i[content_delivered declined],
    content_delivered: %i[completed],
    completed: %i[],
    declined: %i[]
  }.freeze

  belongs_to :contact
  belongs_to :account
  has_many :influencer_offers, dependent: :destroy

  enum :status, { discovered: 0, preselected: 1, enriched: 2, approved: 3, rejected: 4, contacted: 5, confirmed: 6,
                  declined: 7, content_delivered: 8, completed: 9 }
  enum :apify_status, { apify_none: 0, apify_pending: 1, apify_done: 2, apify_failed: 3 }, prefix: :apify

  SUPPORTED_CURRENCIES = %w[EUR GBP PLN].freeze

  validates :username, presence: true, uniqueness: { scope: %i[account_id platform] }
  validates :contact_id, uniqueness: true
  validates :voucher_currency, inclusion: { in: SUPPORTED_CURRENCIES }

  scope :scoreable, -> { where(status: :enriched) }
  scope :actionable, -> { where(status: %i[enriched approved]) }

  def transition_to!(new_status)
    allowed = VALID_TRANSITIONS[status.to_sym] || []
    raise InvalidTransitionError, "Cannot transition from #{status} to #{new_status}" unless allowed.include?(new_status.to_sym)

    update!(status: new_status)
  end

  def tier
    case followers_count.to_i
    when 0...10_000 then :nano
    when 10_000...50_000 then :micro
    when 50_000...500_000 then :mid
    else :macro
    end
  end

  def hidden_likes?
    hidden_like_posts_rate.to_f > 0.5
  end

  def report_available?
    report_fetched_at.present?
  end
end
