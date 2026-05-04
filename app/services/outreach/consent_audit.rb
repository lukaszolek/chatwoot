# Daily self-healing audit between chatwoot's PhotographerPartnerProfile
# and the photographer-directory source-of-truth (Option C exclusion
# notwithstanding, opt-out/do_not_contact state must match).
#
# Two drift directions are detected:
#   1. chatwoot DNC but directory still consenting → re-run ConsentWriter
#      opt-out so directory catches up (previous PropagateConsentJob
#      failed).
#   2. directory has an explicit opt-out/delete/bounce signal but
#      chatwoot shows active participation → pause the profile locally.
#
# Each drift row emits a `consent_drift_detected` audit event and returns
# a summary hash suitable for metrics. The job retries propagation for
# drift #1 via the normal PropagateConsentJob path.
class Outreach::ConsentAudit
  DRIFT_EVENT_TYPE = 'consent_drift_detected'.freeze

  def self.run!
    new.run
  end

  def initialize
    @heal_outbound = 0
    @pause_local = 0
    @errors = 0
  end

  def run
    PhotographerPartnerProfile.do_not_contact.find_each(batch_size: 500) do |profile|
      check_outbound_drift(profile)
    end

    PhotographerPartnerProfile.where.not(partnership_status: :do_not_contact).find_each(batch_size: 500) do |profile|
      check_inbound_drift(profile)
    end

    {
      heal_outbound: @heal_outbound,
      pause_local: @pause_local,
      errors: @errors
    }
  end

  private

  def check_outbound_drift(profile)
    source = find_source(profile)
    return unless source
    return if source.marketing_consent == false && source.unsubscribed_from_all_campaigns == true

    Outreach::PhotographerDirectory::PropagateConsentJob
      .perform_later(profile.id, 'opt_out', reason: 'consent_drift_heal')
    log_drift_event!(profile, direction: 'outbound')
    @heal_outbound += 1
  rescue StandardError => e
    Rails.logger.error("[outreach.consent_audit] profile=#{profile.id} outbound_drift error=#{e.class}")
    @errors += 1
  end

  def check_inbound_drift(profile)
    source = find_source(profile)
    return unless source
    return unless explicit_directory_stop?(source)

    profile.transition_to!(:do_not_contact)
    CampaignParticipant.where(participatable: profile, paused: false).update_all( # rubocop:disable Rails/SkipsModelValidations
      paused: true, updated_at: Time.current
    )
    log_drift_event!(profile, direction: 'inbound')
    @pause_local += 1
  rescue StandardError => e
    Rails.logger.error("[outreach.consent_audit] profile=#{profile.id} inbound_drift error=#{e.class}")
    @errors += 1
  end

  def explicit_directory_stop?(source)
    source.unsubscribed_from_all_campaigns ||
      source.gdpr_delete_requested_at.present? ||
      source.email_validation_status.to_s.start_with?('invalid')
  end

  def find_source(profile)
    PhotographerDirectory::Photographer.find_by(id: profile.external_id)
  rescue StandardError => e
    Rails.logger.warn("[outreach.consent_audit] directory lookup failed for profile=#{profile.id}: #{e.class}")
    nil
  end

  def log_drift_event!(profile, direction:)
    participant = CampaignParticipant.where(participatable: profile).order(:created_at).last
    return unless participant

    CampaignAttributionEvent.create!(
      campaign_participant: participant,
      event_type: DRIFT_EVENT_TYPE,
      occurred_at: Time.current,
      payload: { 'direction' => direction, 'profile_id' => profile.id }
    )
  end
end
