class Influencers::FetchReportJob < ApplicationJob
  queue_as :medium
  retry_on InfluencersClub::Client::ApiError, wait: :polynomially_longer, attempts: 3

  def perform(profile_id)
    profile = InfluencerProfile.find(profile_id)
    unless profile.discovered?
      profile.update!(enrichment_pending: false) if profile.enrichment_pending?
      return
    end

    profile.update!(enrichment_pending: true)
    enrich_profile(profile)
  rescue InfluencersClub::Client::ApiError => e
    handle_api_failure(profile, e)
    raise if retries_remaining?(e)
  end

  private

  def enrich_profile(profile)
    response = InfluencersClub::EnrichService.new.perform(username: profile.username)
    return handle_empty_report(profile) if response.blank?

    attrs = InfluencersClub::ResponseParser.parse_enrich(response)
    return handle_username_mismatch(profile, attrs) if username_mismatch?(profile, attrs)

    apply_enrichment(profile, attrs)
  end

  def apply_enrichment(profile, attrs)
    contact_email = attrs.delete(:_contact_email)
    attrs.delete(:username) # never overwrite the original username
    profile.update!(attrs.merge(report_fetched_at: Time.current, status: :enriched, enrichment_pending: false, last_synced_at: Time.current))
    profile.contact.update!(email: contact_email) if contact_email.present? && profile.contact.email.blank?

    Avatar::AvatarFromUrlJob.perform_later(profile.contact, profile.profile_picture_url) if profile.profile_picture_url.present?
    Influencers::LanguageDetector.detect_and_set(profile)
    Influencers::ScoreProfileJob.perform_later(profile.id)
  end

  def handle_empty_report(profile)
    Rails.logger.warn("[Influencers::FetchReportJob] Empty enrich for profile #{profile.id} (#{profile.username})")
    profile.update!(enrichment_pending: false, rejection_reason: 'Enrichment returned empty report')
  end

  def handle_api_failure(profile, error)
    reason = error.message.include?('credits') ? 'No credits remaining' : "API error: #{error.code}"
    profile.update!(enrichment_pending: false, rejection_reason: "Enrich failed: #{reason}")
    Rails.logger.error("[Influencers::FetchReportJob] Failed for #{profile.username}: #{error.message}")
  end

  def username_mismatch?(profile, attrs)
    returned = attrs[:username]
    returned.present? && returned.downcase != profile.username.downcase
  end

  def handle_username_mismatch(profile, attrs)
    Rails.logger.warn(
      "[Influencers::FetchReportJob] Username mismatch for profile #{profile.id}: " \
      "expected=#{profile.username}, got=#{attrs[:username]}. Storing raw data only."
    )
    profile.update!(raw_report_data: attrs[:raw_report_data], enrichment_pending: false,
                    rejection_reason: "Enrich returned wrong profile: #{attrs[:username]}")
  end

  def retries_remaining?(_error)
    executions < 3
  end
end
