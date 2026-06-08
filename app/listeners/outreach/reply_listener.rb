# Listens for `message.created` events and routes inbound replies on
# campaign-linked conversations back into the outreach engine.
#
# When an inbound (incoming) message lands on a conversation whose
# additional_attributes carry `campaign_participant_id`, the matching
# CampaignParticipant is flipped into `reply_router` and marked due now.
# The next Runner#tick classifies the reply and dispatches via
# branch_rules.
#
# Outgoing messages, private notes, and activity messages are ignored.
# Terminal participants (paused) are ignored — the engine does not
# re-animate them from a late reply.
class Outreach::ReplyListener < BaseListener
  REPLY_ROUTER_STAGE_KEY = 'reply_router'.freeze
  RESUMABLE_PAUSED_REASON_PREFIXES = %w[
    followup_disabled_for_locale:
    manual_freeze_followup_automation
  ].freeze

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless reply_message?(message)

    participant_id = participant_id_for(message)
    return unless participant_id

    participant = CampaignParticipant.find_by(id: participant_id)
    return unless participant
    return handle_non_reply!(participant, message) unless real_reply?(message)

    route_reply!(participant, message)
  end

  private

  def route_reply!(participant, message)
    return if participant.paused? && !resumable_paused_participant?(participant)

    participant.update!(
      paused: false,
      current_stage_key: REPLY_ROUTER_STAGE_KEY,
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      last_inbound_at: Time.current
    )

    bump_status_to_replied!(participant)

    Rails.logger.info(
      "[outreach.reply_listener] participant=#{participant.id} conversation=#{message.conversation_id} " \
      "routed=reply_router message=#{message.id}"
    )
  end

  def real_reply?(message)
    Outreach::InboundMessageKind.call(message) == :reply
  end

  def handle_non_reply!(participant, message)
    kind = Outreach::InboundMessageKind.call(message)
    handle_opt_out!(participant, message) if kind == :opt_out
    metadata = (participant.metadata || {}).merge(
      'last_inbound_kind' => kind.to_s,
      'last_inbound_message_id' => message.id,
      'last_inbound_at' => Time.current.iso8601
    )
    participant.update!(metadata: metadata)
    Rails.logger.info(
      "[outreach.reply_listener] participant=#{participant.id} conversation=#{message.conversation_id} " \
      "ignored_kind=#{kind} message=#{message.id}"
    )
  end

  def handle_opt_out!(participant, message)
    profile = participant.participatable
    ActiveRecord::Base.transaction do
      profile.transition_to!(:do_not_contact) if profile.is_a?(PhotographerPartnerProfile) && !profile.do_not_contact?
      profile.update!(marketing_consent_state: :declined) if profile.is_a?(PhotographerPartnerProfile)
      participant.update!(
        paused: true,
        metadata: (participant.metadata || {}).merge('paused_reason' => 'opt_out', 'opt_out_message_id' => message.id)
      )
    end
    Outreach::PhotographerDirectory::PropagateConsentJob.perform_later(profile.id, 'opt_out', reason: 'inbound_stop') \
      if profile.is_a?(PhotographerPartnerProfile)
  rescue StandardError => e
    Rails.logger.warn("[outreach.reply_listener] opt_out failed: #{e.class}: #{e.message}")
  end

  def resumable_paused_participant?(participant)
    reason = participant.metadata.to_h['paused_reason'].to_s
    RESUMABLE_PAUSED_REASON_PREFIXES.any? { |prefix| reason.start_with?(prefix) }
  end

  # Rough/non-semantic bump just because they replied at all. The
  # downstream ClassifyReply executor will further refine the status
  # based on intent ('interested' for interested_*/asks_*; 'declined'
  # for declined). Status hierarchy (from least to most committed):
  #   imported → contacted → replied → interested → signed_up → completed
  # We only ever move forward; never overwrite a more committed state.
  REPLIED_BUMP_FROM = %w[imported qualified contacted].freeze

  def bump_status_to_replied!(participant)
    profile = participant.participatable
    return unless profile.is_a?(PhotographerPartnerProfile)
    return unless REPLIED_BUMP_FROM.include?(profile.partnership_status.to_s)

    profile.transition_to!(:replied)
  rescue StandardError => e
    Rails.logger.warn("[outreach.reply_listener] partnership_status bump failed: #{e.class}: #{e.message}")
  end

  def reply_message?(message)
    return false unless message
    return false unless message.incoming?
    return false if message.private?

    true
  end

  def participant_id_for(message)
    conversation = message.conversation
    return nil unless conversation

    conversation.additional_attributes.to_h['campaign_participant_id']
  end
end
