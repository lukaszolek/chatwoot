# Marks an outreach draft as rejected and escalates the participant so
# a human operator handles the conversation directly. The rejected draft
# stays in the conversation thread (audit trail).
class Outreach::Drafts::RejectService
  class Error < StandardError; end

  def initialize(draft_message:, user:, reason:)
    @draft_message = draft_message
    @user = user
    @reason = reason.to_s.strip.presence
  end

  def call
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'

    mark_rejected!
    escalate_participant_if_present!
    { ok: true }
  end

  private

  attr_reader :draft_message, :user, :reason

  def mark_rejected!
    draft_message.update!(
      additional_attributes: draft_message.additional_attributes.merge(
        'draft_status' => 'rejected',
        'rejected_by_user_id' => user&.id,
        'rejected_at' => Time.current.iso8601,
        'rejected_reason' => reason
      )
    )
  end

  def escalate_participant_if_present!
    pid = draft_message.additional_attributes['campaign_participant_id']
    return unless pid

    participant = CampaignParticipant.find_by(id: pid)
    return unless participant

    metadata = (participant.metadata || {}).merge(
      'escalation_reason' => "draft_rejected:#{reason || 'unspecified'}"
    )
    participant.update!(
      current_stage_key: 'escalated',
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      metadata: metadata
    )
  end
end
