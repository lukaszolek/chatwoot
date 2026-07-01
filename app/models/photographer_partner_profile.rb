# Chatwoot-side outreach state for one photographer. PII (email, name,
# website, IG, phone, country, language, source consent) lives ONLY in
# photographer_directory.photographer_photographers; this row just holds:
#   - external_id   : pointer to the directory row (string because
#                     directory primary key is legacy)
#   - outreach state: partnership_status, tri-state marketing_consent_state,
#                     notes, tags, metadata, contact_id
#
# Reads of .email / .business_name / .owner_name / etc. fan out to the
# secondary DB through #source. If the directory is unreachable (VPN,
# crashed secondary) those readers return nil — the callers MUST handle
# it. Single-source-of-truth is the goal; offline behavior is the
# trade-off.
# == Schema Information
#
# Table name: photographer_partner_profiles
#
#  id                            :bigint           not null, primary key
#  first_order_completed_at      :datetime
#  last_order_completed_at       :datetime
#  marketing_consent_state       :integer          default("unknown"), not null
#  metadata                      :jsonb            not null
#  notes                         :text
#  order_stats_refreshed_at      :datetime
#  orders_last_30d               :integer          default(0), not null
#  orders_last_90d               :integer          default(0), not null
#  orders_total                  :integer          default(0), not null
#  partnership_status            :integer          default("imported"), not null
#  partnership_status_changed_at :datetime
#  tags                          :string           default([]), is an Array
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  contact_id                    :bigint
#  external_id                   :string           not null
#
# Indexes
#
#  idx_on_order_stats_refreshed_at_0d81e748c4                      (order_stats_refreshed_at)
#  idx_photographer_profiles_account_external                      (account_id,external_id) UNIQUE
#  index_photographer_partner_profiles_on_account_id               (account_id)
#  index_photographer_partner_profiles_on_contact_id               (contact_id)
#  index_photographer_partner_profiles_on_last_order_completed_at  (last_order_completed_at)
#  index_photographer_partner_profiles_on_marketing_consent_state  (marketing_consent_state)
#  index_photographer_partner_profiles_on_partnership_status       (partnership_status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#
class PhotographerPartnerProfile < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true
  has_many :campaign_participants, as: :participatable # rubocop:disable Rails/HasManyOrHasOneDependent

  # Tri-state consent — source of truth on the chatwoot side.
  # (photographer-directory still has its own boolean consent, which
  # writes flow back to via ConsentWriter; the tri-state exists so
  # operators can capture the uncertain middle explicitly.)
  enum :marketing_consent_state, {
    unknown: 0,
    granted: 1,
    declined: 2
  }, prefix: :consent

  enum :partnership_status, {
    imported: 0,
    qualified: 1,
    contacted: 2,
    replied: 3,
    interested: 4,
    signed_up: 5,
    declined: 6,
    do_not_contact: 7,
    completed: 8
  }

  validates :external_id, presence: true,
                          uniqueness: { scope: :account_id }

  scope :active_outreach, -> { where.not(partnership_status: %i[do_not_contact completed]) }

  # PII delegation — all of these read live from the directory row.
  DIRECTORY_DELEGATED_FIELDS = %i[
    email
    business_name
    owner_name
    website
    country_code
    phone
    instagram_handle
    marketing_consent
    unsubscribed_from_all_campaigns
    gdpr_delete_requested_at
    status
    google_rating
    google_review_count
  ].freeze

  delegate(*DIRECTORY_DELEGATED_FIELDS, to: :source, allow_nil: true)

  # preferred_language is a computed field (not a direct directory
  # column). We derive it from directory's native_language + country_code,
  # with a safe fallback.
  COUNTRY_TO_LOCALE = {
    'pl' => 'pl', 'de' => 'de', 'at' => 'de', 'ch' => 'de',
    'fr' => 'fr', 'be' => 'fr', 'gb' => 'en', 'us' => 'en', 'ie' => 'en',
    'es' => 'es', 'it' => 'it', 'nl' => 'nl', 'cz' => 'cs',
    'sk' => 'sk', 'hu' => 'hu', 'ro' => 'ro', 'hr' => 'hr',
    'dk' => 'da', 'fi' => 'fi', 'se' => 'sv', 'gr' => 'el'
  }.freeze

  def preferred_language
    return nil unless source

    source.native_language.presence ||
      COUNTRY_TO_LOCALE[source.country_code.to_s.downcase] ||
      source.preferred_language.presence ||
      'en'
  end

  # The directory row. Memoized per instance; instance-level cache reset
  # with #reload. If the secondary DB is down, returns nil and delegated
  # PII readers become nil.
  def source
    @source ||= PhotographerDirectory::Photographer.find_by(id: external_id)
  rescue StandardError => e
    Rails.logger.warn("[photographer_partner_profile##{id}] directory lookup failed: #{e.class}: #{e.message}")
    nil
  end

  # Batch preloader for listings — avoids N+1 directory hits. Caller
  # hands us a Relation of profiles; we pull all source rows in one IN
  # query and pre-fill each profile's memoized @source.
  def self.preload_sources!(profiles)
    ids = profiles.filter_map(&:external_id).uniq
    return profiles if ids.empty?

    sources_by_id = PhotographerDirectory::Photographer.where(id: ids).index_by { |s| s.id.to_s }
    profiles.each do |p|
      p.instance_variable_set(:@source, sources_by_id[p.external_id.to_s])
    end
    profiles
  end

  def reload(*)
    @source = nil
    super
  end

  # ------------------------------------------------------------------
  # Outreach pipeline (chatwoot-only state, not propagated)
  # ------------------------------------------------------------------

  PIPELINE_STAGES = %w[new interested signed_up first_order active dormant_30d dormant_90d do_not_contact].freeze
  TERMINAL_PIPELINE_STATUSES = %w[declined completed].freeze

  def pipeline_stage
    return nil if TERMINAL_PIPELINE_STATUSES.include?(partnership_status)

    order_pipeline_stage || status_pipeline_stage
  end

  def order_pipeline_stage
    return nil if orders_total.to_i < 1 || last_order_completed_at.blank?

    days = ((Time.current - last_order_completed_at) / 1.day).to_i
    return 'dormant_90d' if days >= 90
    return 'dormant_30d' if days >= 30
    return 'active' if orders_total.to_i >= 2

    'first_order'
  end

  def status_pipeline_stage
    case partnership_status.to_s
    when 'do_not_contact' then 'do_not_contact'
    when 'signed_up' then 'signed_up'
    when 'interested' then 'interested'
    else 'new'
    end
  end

  def transition_to!(new_status)
    update!(
      partnership_status: new_status,
      partnership_status_changed_at: Time.current
    )
  end
end
