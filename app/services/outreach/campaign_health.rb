class Outreach::CampaignHealth
  RECENT_ERRORS_LIMIT = 5
  GENERATION_ERRORS_LIST_LIMIT = 100

  def initialize(campaign)
    @campaign = campaign
  end

  def summary
    {
      missing_drafts_count: missing_drafts.count,
      generation_error_count: generation_errors.count,
      llm_credits_error_count: llm_credits_errors.count,
      stale_processing_count: stale_processing.count,
      recent_generation_errors: recent_generation_errors,
      generation_error_items: generation_error_items
    }
  end

  private

  attr_reader :campaign

  def missing_drafts
    @missing_drafts ||= campaign.participants
                                .where(conversation_id: nil)
                                .where(current_stage_key: 'intro')
  end

  def generation_errors
    @generation_errors ||= campaign.participants
                                   .where(current_stage_key: 'intro')
                                   .where("metadata ? 'last_error'")
  end

  def llm_credits_errors
    @llm_credits_errors ||= generation_errors.where(
      "metadata->>'last_error' ILIKE ? OR metadata->>'last_error' ILIKE ?",
      '%PaymentRequired%',
      '%credits%'
    )
  end

  def stale_processing
    @stale_processing ||= missing_drafts
                          .where(paused: false)
                          .where(next_action_at: nil)
                          .where("metadata ? 'processing_started_at'")
  end

  def recent_generation_errors
    generation_error_payloads(limit: RECENT_ERRORS_LIMIT)
  end

  def generation_error_items
    generation_error_payloads(limit: GENERATION_ERRORS_LIST_LIMIT)
  end

  def generation_error_payloads(limit:)
    participants = generation_errors
                   .includes(:participatable)
                   .order(Arel.sql("metadata->>'last_error_at' DESC NULLS LAST"), updated_at: :desc)
                   .limit(limit)
                   .to_a
    preload_profile_sources!(participants)

    participants.map { |participant| error_payload(participant) }
  end

  def preload_profile_sources!(participants)
    profiles = participants.filter_map do |participant|
      participant.participatable if participant.participatable_type == 'PhotographerPartnerProfile'
    end
    PhotographerPartnerProfile.preload_sources!(profiles) if profiles.any?
  end

  def error_payload(participant)
    profile = participant.participatable
    {
      participant_id: participant.id,
      profile_id: profile&.id,
      profile_name: profile_name(profile),
      email: profile&.try(:email),
      country_code: profile&.try(:country_code),
      locale: profile&.try(:preferred_language),
      stage: participant.current_stage_key,
      next_action_at: participant.next_action_at&.to_i,
      last_error: participant.metadata['last_error'],
      last_error_at: timestamp_from_metadata(participant, 'last_error_at'),
      processing_started_at: timestamp_from_metadata(participant, 'processing_started_at')
    }
  end

  def profile_name(profile)
    return nil unless profile

    profile.try(:business_name).presence ||
      profile.try(:owner_name).presence ||
      profile.try(:email).presence ||
      "profile##{profile.id}"
  end

  def timestamp_from_metadata(participant, key)
    value = participant.metadata[key]
    return nil if value.blank?

    Time.zone.parse(value).to_i
  rescue ArgumentError, TypeError
    nil
  end
end
