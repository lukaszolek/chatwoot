# Promotes an outreach draft Message (private: true,
# additional_attributes['outreach_draft'] = true) into a real outgoing
# Message that the channel will deliver, then advances the participant.
#
#   - Marks draft.draft_status = 'approved' (kept in the thread as
#     audit trail).
#   - Enqueues Outreach::SendEmailJob with subject/body from the draft.
#   - Advances the participant to next_stage_key (intro → reminder_wait,
#     reminder_send → breakup_wait, etc.) and stamps last_outbound_at.
#
# For the `reply` slot — there's no obvious "next" stage in the
# blueprint (reply_router routes by classifier intent), so we just
# return the participant to terminal after sending the operator-approved
# reply.
class Outreach::Drafts::ApproveService
  class Error < StandardError; end

  def initialize(draft_message:, user:)
    @draft_message = draft_message
    @user = user
  end

  def call
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'

    participant = resolve_participant
    raise Error, 'participant not found' unless participant

    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: draft_message.conversation_id,
      subject: draft_message.outreach_draft_subject,
      body: draft_message.content,
      template_slot: draft_message.additional_attributes['template_slot'],
      locale: draft_message.additional_attributes['locale']
    )

    mark_approved!
    advance_participant!(participant)

    { sent_message_id: nil, advanced_to: participant.reload.current_stage_key }
  end

  private

  attr_reader :draft_message, :user

  def resolve_participant
    pid = draft_message.additional_attributes['campaign_participant_id']
    pid ? CampaignParticipant.find_by(id: pid) : nil
  end

  def mark_approved!
    draft_message.update!(
      additional_attributes: draft_message.additional_attributes.merge(
        'draft_status' => 'approved',
        'approved_by_user_id' => user&.id,
        'approved_at' => Time.current.iso8601
      )
    )
  end

  def advance_participant!(participant)
    stage = participant.outbound_campaign.pipeline_stages.find_by(key: participant.current_stage_key)
    next_key = stage&.next_stage_key.presence || 'terminal'
    participant.update!(
      current_stage_key: next_key,
      stage_entered_at: Time.current,
      next_action_at: Time.current,
      last_outbound_at: Time.current
    )
  end
end
