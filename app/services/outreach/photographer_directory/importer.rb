# Pulls photographer leads from the photographer-directory secondary DB
# into `PhotographerPartnerProfile` on the chatwoot side. Idempotent:
# running it repeatedly only touches rows whose source attributes changed.
#
# Exclusion scope (Option C): photographers currently enrolled in another
# photographer-directory campaign (active `photographer_campaign_status`
# row) are skipped, so the partnership outreach never double-mails someone
# who is already in the onboarding CRM.
#
# On each imported row we also ensure a chatwoot `Contact` exists, linked
# via `profile.contact_id`, identified by the source external_id so the
# reverse lookup from Contact → PhotographerPartnerProfile stays stable.
class Outreach::PhotographerDirectory::Importer
  BATCH_SIZE = 1_000
  CONTACT_IDENTIFIER_PREFIX = 'photographer_directory'.freeze

  Result = Struct.new(:imported, :updated, :skipped, :failed, keyword_init: true) do
    def total
      imported + updated + skipped + failed
    end
  end

  def initialize(account:, country: nil, batch_size: BATCH_SIZE)
    @account = account
    @country = country
    @batch_size = batch_size
  end

  def perform
    stats = { imported: 0, updated: 0, skipped: 0, failed: 0 }

    source_query.find_in_batches(batch_size: @batch_size) do |batch|
      batch.each do |source|
        stats[process_one(source)] += 1
      rescue StandardError => e
        stats[:failed] += 1
        Rails.logger.error(
          "[outreach.importer] failed for photographer_id=#{source.id}: #{e.class}: #{e.message}"
        )
      end
    end

    Result.new(**stats)
  end

  private

  attr_reader :account, :country

  def source_query
    scope = ::PhotographerDirectory::Photographer.queryable_for_outreach
    scope = scope.where(country_code: country) if country.present?
    scope.where.not(
      id: ::PhotographerDirectory::CampaignStatus.active_enrolment.select(:photographer_id)
    )
  end

  def process_one(source)
    profile = ::PhotographerPartnerProfile.find_or_initialize_by(
      account: account,
      external_id: source.id.to_s
    )
    was_new = profile.new_record?
    was_do_not_contact = !was_new && profile.do_not_contact?

    ActiveRecord::Base.transaction do
      contact = ensure_contact(source)
      profile.assign_attributes(build_attrs(source, contact))
      profile.partnership_status = :imported if was_new
      flag_reenrollment(profile, was_do_not_contact)
      profile.last_synced_at = Time.current
      profile.save!
    end

    was_new ? :imported : :updated
  end

  def ensure_contact(source)
    identifier = "#{CONTACT_IDENTIFIER_PREFIX}:#{source.id}"
    contact = account.contacts.find_by(identifier: identifier)
    return contact if contact

    account.contacts.create!(
      identifier: identifier,
      email: source.email,
      name: source.owner_name.presence || source.business_name.presence || source.email,
      phone_number: source.phone.presence,
      contact_type: :lead,
      additional_attributes: {
        'website' => source.website,
        'instagram_handle' => source.instagram_handle,
        'country_code' => source.country_code,
        'source' => CONTACT_IDENTIFIER_PREFIX
      }.compact
    )
  end

  def build_attrs(_source, contact)
    # Only contact_id is persisted here. All other fields (email,
    # business_name, etc.) live on PhotographerDirectory::Photographer and
    # are read via delegation — no copies stored on PhotographerPartnerProfile.
    { contact_id: contact.id }
  end

  def flag_reenrollment(profile, was_do_not_contact)
    # Directory is source of truth for consent. If the directory now
    # reports marketing_consent=true for someone we previously marked
    # `do_not_contact` in chatwoot, surface that to the operator via
    # metadata rather than silently re-enrolling (§9.10).
    return unless was_do_not_contact

    profile.metadata = profile.metadata.merge('previously_do_not_contact' => true)
    profile.partnership_status = :imported
  end
end
