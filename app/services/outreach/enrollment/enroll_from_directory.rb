# Idempotent enrollment from the photographer-directory secondary DB into
# the chatwoot outreach pipeline. For each directory row it:
#
#   1. Finds or creates a PhotographerPartnerProfile (scoped per account,
#      keyed on directory.id as external_id).
#   2. Creates a chatwoot Contact if missing (same identifier pattern as
#      the bulk Importer so future syncs line up).
#   3. Creates a CampaignParticipant in the `photographer_partnership`
#      campaign at stage=intro, next_action_at=now, so the next engine
#      tick picks it up.
#
# Returns a Result with per-row outcomes so the UI can show what
# happened. Skips rows already enrolled (participant exists) and rows
# whose profile is in do_not_contact.
class Outreach::Enrollment::EnrollFromDirectory
  Result = Struct.new(:enrolled, :re_enrolled, :already_enrolled, :skipped_dnc, :failed, :errors, keyword_init: true)

  CONTACT_IDENTIFIER_PREFIX = 'photographer_directory'.freeze

  def initialize(account:, directory_ids:)
    @account = account
    @directory_ids = Array(directory_ids).map(&:to_s).uniq
  end

  def perform
    result = Result.new(enrolled: 0, re_enrolled: 0, already_enrolled: 0, skipped_dnc: 0, failed: 0, errors: [])
    campaign = find_partnership_campaign!

    PhotographerDirectory::Photographer.where(id: @directory_ids).find_each do |source|
      process_one(source, campaign, result)
    rescue StandardError => e
      result.failed += 1
      result.errors << { directory_id: source&.id, message: "#{e.class}: #{e.message}" }
      Rails.logger.error("[outreach.enroll_from_directory] failed id=#{source&.id}: #{e.class}: #{e.message}")
    end

    result
  end

  private

  attr_reader :account

  def find_partnership_campaign!
    campaign = account.outbound_campaigns.find_by(program_key: 'photographer_partnership')
    raise ActiveRecord::RecordNotFound, 'photographer_partnership campaign not found — run rake outreach:blueprints:apply' unless campaign

    campaign
  end

  def process_one(source, campaign, result)
    ActiveRecord::Base.transaction do
      profile = upsert_profile(source)

      if profile.do_not_contact?
        result.skipped_dnc += 1
        next
      end

      participant = CampaignParticipant.find_by(outbound_campaign: campaign, participatable: profile)
      if participant
        handle_existing(participant, result)
      else
        create_participant!(campaign, profile)
        result.enrolled += 1
      end
    end
  end

  def handle_existing(participant, result)
    if participant.paused?
      participant.update!(paused: false, next_action_at: Time.current,
                          current_stage_key: 'intro', stage_entered_at: Time.current)
      result.re_enrolled += 1
    else
      result.already_enrolled += 1
    end
  end

  def create_participant!(campaign, profile)
    CampaignParticipant.create!(
      outbound_campaign: campaign, account: account, participatable: profile,
      current_stage_key: 'intro', stage_entered_at: Time.current, next_action_at: Time.current
    )
  end

  def upsert_profile(source)
    profile = account.photographer_partner_profiles.find_or_initialize_by(external_id: source.id.to_s)
    contact = ensure_contact(source)
    profile.assign_attributes(
      email: source.email, business_name: source.business_name, owner_name: source.owner_name,
      website: source.website, country_code: source.country_code&.upcase,
      preferred_language: resolve_locale(source),
      instagram_handle: source.instagram_handle, marketing_consent: source.marketing_consent,
      source_status: source.status, contact_id: contact&.id, last_synced_at: Time.current
    )
    # Consent state only set when (re)importing fresh. Never overwrite
    # operator-set state — once someone manually flips granted/declined
    # in chatwoot UI, importer should not silently revert it.
    profile.marketing_consent_state = derive_consent_state(source) if profile.new_record?
    profile.partnership_status = :imported if profile.new_record?
    profile.save!
    profile
  end

  def derive_consent_state(source)
    return :declined if source.unsubscribed_from_all_campaigns
    return :granted if source.marketing_consent

    :unknown
  end

  # Resolution rule: photographer-directory's `preferred_language` stores
  # the UI edit-interface language (e.g. a Polish photographer who read
  # the directory UI in English has preferred_language='en'). For
  # outreach mails we need the language the PERSON speaks, so:
  #   1. `native_language` first (most reliable when set)
  #   2. country_code → locale map (PL→pl, DE→de, FR→fr, …)
  #   3. `preferred_language` (least reliable, but better than nothing)
  #   4. 'en' as a safe last resort
  COUNTRY_TO_LOCALE = {
    'pl' => 'pl', 'de' => 'de', 'at' => 'de', 'ch' => 'de',
    'fr' => 'fr', 'be' => 'fr', 'gb' => 'en', 'us' => 'en', 'ie' => 'en',
    'es' => 'es', 'it' => 'it', 'nl' => 'nl', 'cz' => 'cs',
    'sk' => 'sk', 'hu' => 'hu', 'ro' => 'ro', 'hr' => 'hr',
    'dk' => 'da', 'fi' => 'fi', 'se' => 'sv', 'gr' => 'el'
  }.freeze

  def resolve_locale(source)
    source.native_language.presence ||
      COUNTRY_TO_LOCALE[source.country_code.to_s.downcase] ||
      source.preferred_language.presence ||
      'en'
  end

  def ensure_contact(source)
    identifier = "#{CONTACT_IDENTIFIER_PREFIX}:#{source.id}"
    contact = account.contacts.find_by(identifier: identifier)
    contact || account.contacts.create!(
      identifier: identifier, email: source.email,
      name: (source.owner_name.presence || source.business_name.presence || source.email)
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
