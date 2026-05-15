# == Schema Information
#
# Table name: influencer_offers
#
#  id                      :bigint           not null, primary key
#  available_packages      :jsonb
#  consent_data_processing :boolean          default(FALSE)
#  consent_terms           :boolean          default(FALSE)
#  custom_message          :text
#  expires_at              :datetime
#  offer_page_version      :string
#  referral_link           :string
#  rights_level            :string           default("standard")
#  selected_packages       :jsonb
#  status                  :integer          default("pending"), not null
#  terms_accepted_at       :datetime
#  token                   :string           not null
#  voucher_code            :string
#  voucher_currency        :string           default("EUR")
#  voucher_value           :decimal(10, 2)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  created_by_id           :bigint
#  influencer_profile_id   :bigint           not null
#
# Indexes
#
#  index_influencer_offers_on_account_id             (account_id)
#  index_influencer_offers_on_created_by_id          (created_by_id)
#  index_influencer_offers_on_influencer_profile_id  (influencer_profile_id)
#  index_influencer_offers_on_token                  (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (influencer_profile_id => influencer_profiles.id)
#
class InfluencerOffer < ApplicationRecord
  CURRENT_OFFER_PAGE_VERSION = '1.0'.freeze

  belongs_to :influencer_profile
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  enum :status, { pending: 0, accepted: 1, expired: 2, revoked: 3 }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  validates :token, presence: true, uniqueness: true

  def offer_path
    "/offer/#{token}"
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def referral_url
    "https://framky.com/#{influencer_profile.username}"
  end

  def calculate_voucher_value(packages, rights)
    Influencers::VoucherCalculator.new(
      followers: influencer_profile.followers_count,
      fqs_score: influencer_profile.fqs_score,
      packages: packages,
      rights: rights,
      multiplier: influencer_profile.voucher_value_multiplier
    ).value
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(24)
  end

  def set_expiry
    self.expires_at ||= 14.days.from_now
  end
end
