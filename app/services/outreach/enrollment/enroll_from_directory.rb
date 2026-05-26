# Idempotent enrollment from the photographer-directory secondary DB into
# the chatwoot outreach pipeline.
#
# Since SSOT for PII lives in photographer-directory, we no longer copy
# photographer fields into chatwoot. The local profile row is now just a
# pointer (external_id) + outreach state (partnership_status,
# marketing_consent_state, notes, tags). PII is read live via delegation
# through PhotographerPartnerProfile#source.
#
# This service still:
#   1. Finds or creates a PhotographerPartnerProfile keyed on external_id.
#   2. Ensures a chatwoot Contact exists (used for conversation threading;
#      independent concept from the directory row).
#   3. Creates a CampaignParticipant at stage=intro so the engine tick
#      will generate and (depending on manual_review_mode) send or queue
#      the intro mail.
class Outreach::Enrollment::EnrollFromDirectory
  Result = Struct.new(:enrolled, :re_enrolled, :already_enrolled, :skipped_dnc,
                      :skipped_duplicate_email, :failed, :errors, keyword_init: true)

  CONTACT_IDENTIFIER_PREFIX = 'photographer_directory'.freeze

  def initialize(account:, directory_ids:)
    @account = account
    @directory_ids = Array(directory_ids).map(&:to_s).uniq
  end

  def perform
    result = Result.new(enrolled: 0, re_enrolled: 0, already_enrolled: 0,
                        skipped_dnc: 0, skipped_duplicate_email: 0, failed: 0, errors: [])
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
        handle_existing(participant, source, result)
      elsif duplicate_email_participant?(campaign, profile)
        result.skipped_duplicate_email += 1
      else
        create_participant!(campaign, profile)
        remember_campaign_email!(source.email)
        result.enrolled += 1
      end
    end
  end

  def handle_existing(participant, source, result)
    if participant.paused?
      participant.update!(paused: false, next_action_at: Time.current,
                          current_stage_key: 'intro', stage_entered_at: Time.current)
      remember_campaign_email!(source.email)
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

  def duplicate_email_participant?(campaign, profile)
    contact = profile.contact
    email = profile.email.to_s.downcase.strip
    return false if contact.blank? && email.blank?

    return true if duplicate_contact_participant?(campaign, profile, contact)

    duplicate_profile_email_participant?(campaign, email)
  end

  def duplicate_contact_participant?(campaign, profile, contact)
    return false unless contact

    campaign.participants
            .where(account: account, participatable_type: 'PhotographerPartnerProfile')
            .where.not(paused: true)
            .where.not(participatable_id: profile.id)
            .joins('INNER JOIN photographer_partner_profiles ppp ON ppp.id = campaign_participants.participatable_id')
            .exists?(ppp: { contact_id: contact.id })
  end

  def duplicate_profile_email_participant?(campaign, email)
    normalized_email = normalize_email(email)
    return false if normalized_email.blank?

    campaign_email_index(campaign).include?(normalized_email)
  end

  def campaign_email_index(campaign)
    @campaign_email_index ||= build_campaign_email_index(campaign)
  end

  def build_campaign_email_index(campaign)
    external_ids = PhotographerPartnerProfile
                   .where(account: account, id: campaign.participants
                                             .where(participatable_type: 'PhotographerPartnerProfile')
                                             .where.not(paused: true)
                                             .select(:participatable_id))
                   .pluck(:external_id)
                   .compact

    PhotographerDirectory::Photographer
      .where(id: external_ids)
      .pluck(:email)
      .filter_map { |email| normalize_email(email).presence }
      .to_set
  end

  def remember_campaign_email!(email)
    normalized_email = normalize_email(email)
    return if normalized_email.blank?

    @campaign_email_index&.add(normalized_email)
  end

  def normalize_email(email)
    email.to_s.downcase.strip
  end

  def upsert_profile(source)
    profile = account.photographer_partner_profiles.find_or_initialize_by(external_id: source.id.to_s)

    if profile.new_record?
      # On first import: snap up the operator-side state defaults. Once
      # we save, PII reads are live from the directory via delegation.
      profile.contact = ensure_contact(source)
      profile.partnership_status = :imported
      profile.marketing_consent_state = derive_consent_state(source)
    elsif profile.contact_id.blank?
      # Existing profile without contact — ensure one (older imports may
      # have had contact creation fail).
      profile.contact = ensure_contact(source)
    end

    profile.save!
    profile
  end

  def derive_consent_state(source)
    return :declined if source.unsubscribed_from_all_campaigns
    return :granted if source.marketing_consent

    :unknown
  end

  def ensure_contact(source) # rubocop:disable Metrics/AbcSize
    identifier = "#{CONTACT_IDENTIFIER_PREFIX}:#{source.id}"
    # Identifier-first: the canonical link when chatwoot has already
    # imported this directory row before.
    contact = account.contacts.find_by(identifier: identifier)
    return contact if contact

    # Email fallback: a prior import (or manual contact creation) may
    # have left a row with the same email but different identifier.
    # Adopt it by stamping the identifier on and reusing.
    by_email = account.contacts.where('LOWER(email) = ?', source.email.to_s.downcase).first
    if by_email
      by_email.update!(identifier: identifier) if by_email.identifier != identifier
      return by_email
    end

    account.contacts.create!(
      identifier: identifier, email: source.email,
      name: (source.owner_name.presence || source.business_name.presence || source.email)
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[outreach.enroll] ensure_contact failed: #{e.message}")
    nil
  end
end
