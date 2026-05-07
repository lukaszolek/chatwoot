class Outreach::ConversationActionService
  class Error < StandardError; end

  REPLY_ROUTER_STAGE_KEY = 'reply_router'.freeze
  REPLIED_BUMP_FROM = %w[imported qualified contacted].freeze

  def initialize(conversation:, action:, user: nil)
    @conversation = conversation
    @action = action.to_s
    @user = user
  end

  def call
    case action
    when 'mark_bounced' then mark_bounced!
    when 'mark_auto_reply' then mark_auto_reply!
    when 'mark_opt_out' then mark_opt_out!
    when 'needs_reply' then needs_reply!
    when 'resolve' then resolve!
    else raise Error, "unsupported_action:#{action}"
    end
  end

  private

  attr_reader :conversation, :action, :user

  def participant
    @participant ||= CampaignParticipant.find_by(id: conversation.additional_attributes.to_h['campaign_participant_id'])
  end

  def profile
    @profile ||= participant&.participatable
  end

  def mark_bounced!
    Outreach::ConversationLabels.mark_bounced!(conversation)
    pause_participant!('operator_mark_bounced')
  end

  def mark_auto_reply!
    Outreach::ConversationLabels.mark_auto_reply!(conversation)
    stamp_participant_metadata!('operator_mark_auto_reply')
  end

  def mark_opt_out!
    ActiveRecord::Base.transaction do
      profile.transition_to!(:do_not_contact) if profile.is_a?(PhotographerPartnerProfile) && !profile.do_not_contact?
      profile.update!(marketing_consent_state: :declined) if profile.is_a?(PhotographerPartnerProfile)
      pause_participant!('operator_mark_opt_out')
      Outreach::ConversationLabels.mark_opt_out!(conversation)
    end
    Outreach::PhotographerDirectory::PropagateConsentJob.perform_later(profile.id, 'opt_out', reason: 'operator_manual') \
      if profile.is_a?(PhotographerPartnerProfile)
  end

  def needs_reply!
    Outreach::ConversationLabels.mark_replied!(conversation)
    return unless participant

    participant.update!(
      paused: false,
      current_stage_key: REPLY_ROUTER_STAGE_KEY,
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      metadata: participant.metadata.to_h.merge('operator_marked_needs_reply_by_user_id' => user&.id)
    )
    bump_status_to_replied!
  end

  def resolve!
    conversation.resolved!
  end

  def pause_participant!(reason)
    return unless participant

    participant.update!(
      paused: true,
      next_action_at: nil,
      metadata: participant.metadata.to_h.merge('paused_reason' => reason, 'operator_action_by_user_id' => user&.id)
    )
  end

  def stamp_participant_metadata!(reason)
    return unless participant

    participant.update!(
      metadata: participant.metadata.to_h.merge('last_operator_action' => reason, 'operator_action_by_user_id' => user&.id)
    )
  end

  def bump_status_to_replied!
    return unless profile.is_a?(PhotographerPartnerProfile)
    return unless REPLIED_BUMP_FROM.include?(profile.partnership_status.to_s)

    profile.transition_to!(:replied)
  end
end
