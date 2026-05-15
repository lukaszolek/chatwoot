# Promotes an outreach draft Message (private: true,
# additional_attributes['outreach_draft'] = true) into a real outgoing
# Message that the channel will deliver, then advances the participant.
#
#   - Marks draft.draft_status = 'approved' (kept in the thread as
#     audit trail).
#   - Enqueues Outreach::SendEmailJob with subject/body from the draft.
#   - Outreach::SendEmailJob advances the participant only after it creates
#     the real public outgoing message.
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

    validate_stop_opt_out!
    enqueue_email!(participant)
    mark_approved!

    { sent_message_id: nil, advanced_to: participant.reload.current_stage_key }
  end

  private

  attr_reader :draft_message, :user

  def resolve_participant
    pid = draft_message.additional_attributes['campaign_participant_id']
    pid ? CampaignParticipant.find_by(id: pid) : nil
  end

  def stop_opt_out_required?
    draft_message.additional_attributes['template_slot'].to_s != 'reply'
  end

  def missing_stop_opt_out?
    !Outreach::LegalFooter.stop_opt_out_present?(draft_message.content)
  end

  def validate_stop_opt_out!
    return unless stop_opt_out_required? && missing_stop_opt_out?

    raise Error, 'draft is missing STOP opt-out'
  end

  def enqueue_email!(participant)
    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: draft_message.conversation_id,
      subject: draft_message.outreach_draft_subject,
      body: draft_message.content,
      template_slot: draft_message.additional_attributes['template_slot'],
      locale: draft_message.additional_attributes['locale']
    )
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
end
