# Records a partnership signup (framky.com -> chatwoot webhook).
# Idempotent: re-posting the same signup does not duplicate events or
# private notes. Called only by
# `Webhooks::Outreach::PartnershipSignupsController` after HMAC verification.
class Outreach::Attribution::SignupRecorder
  class ProfileNotFound < StandardError; end

  SIGNUP_EVENT_TYPE = 'partnership_signup'.freeze

  def initialize(payload)
    @payload = payload.transform_keys(&:to_s)
  end

  def call
    profile = resolve_profile!
    participant = resolve_participant(profile)

    ActiveRecord::Base.transaction do
      profile.transition_to!(:signed_up) unless profile.signed_up?
      participant&.update!(current_stage_key: 'terminal', paused: true, stage_entered_at: Time.current)
      ensure_signup_note(participant)
      ensure_attribution_event(profile, participant)
    end

    { profile: profile, participant: participant }
  end

  private

  def resolve_profile!
    profile = PhotographerPartnerProfile.find_by(external_id: @payload['external_id']) ||
              profile_by_email
    raise ProfileNotFound, "no profile for external_id=#{@payload['external_id']} email=#{@payload['email']}" unless profile

    profile
  end

  # PII (email) lives only in photographer-directory, so we resolve the
  # source row first and look up the profile by external_id.
  def profile_by_email
    email = @payload['email'].to_s.downcase
    return nil if email.blank?

    directory_id = PhotographerDirectory::Photographer
                   .where('LOWER(email) = ?', email)
                   .limit(1)
                   .pick(:id)
    return nil if directory_id.blank?

    PhotographerPartnerProfile.find_by(external_id: directory_id.to_s)
  end

  def resolve_participant(profile)
    if (pid = @payload.dig('utm', 'participant_id') || @payload['participant_id']).present?
      CampaignParticipant.find_by(id: pid)
    else
      CampaignParticipant.where(participatable: profile).order(:created_at).last
    end
  end

  def ensure_attribution_event(profile, participant)
    return unless participant

    existing = CampaignAttributionEvent.exists?(campaign_participant: participant, event_type: SIGNUP_EVENT_TYPE)
    return if existing

    CampaignAttributionEvent.create!(
      campaign_participant: participant,
      event_type: SIGNUP_EVENT_TYPE,
      occurred_at: parsed_signed_up_at,
      payload: {
        'email' => profile.email,
        'external_id' => profile.external_id,
        'handle' => @payload['handle'],
        'utm' => @payload['utm']
      }.compact
    )
  end

  def ensure_signup_note(participant)
    return unless participant&.conversation

    handle = @payload['handle'].to_s.strip
    note_text = handle.empty? ? 'Zarejestrowany na framky.com' : "Zarejestrowany na framky.com jako @#{handle}"
    note_text = "✅ #{note_text}"
    existing = participant.conversation.messages.where(private: true).exists?(['content = ?', note_text])
    return if existing

    participant.conversation.messages.create!(
      account: participant.conversation.account,
      inbox: participant.conversation.inbox,
      message_type: :outgoing,
      private: true,
      content: note_text,
      content_type: 'text'
    )
  end

  def parsed_signed_up_at
    raw = @payload['signed_up_at']
    return Time.current if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError
    Time.current
  end
end
