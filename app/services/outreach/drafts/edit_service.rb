# Operator manually edits an outreach draft's subject and/or body
# in-place. We diff the old vs new, persist the change, and record an
# OutboundCampaignLearning row with source_kind = 'operator_edit' so
# future composer calls see what kind of edit the operator preferred.
#
# The operator can also pass a `learning_note` to capture WHY they made
# the edit (more useful for future generations than just the diff).
class Outreach::Drafts::EditService
  class Error < StandardError; end

  def initialize(draft_message:, user:, subject:, body:, learning_note: nil)
    @draft_message = draft_message
    @user = user
    @subject = subject.to_s
    @body = body.to_s
    @learning_note = learning_note.to_s.strip.presence
  end

  def call
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'
    raise Error, 'subject and body are required' if subject.empty? && body.empty?

    prev_subject = draft_message.outreach_draft_subject
    prev_body = draft_message.content
    return { ok: true, no_changes: true } if prev_subject == subject && prev_body == body

    apply_edit!(prev_subject, prev_body)
    record_learning!(prev_subject, prev_body)
    { ok: true }
  end

  private

  attr_reader :draft_message, :user, :subject, :body, :learning_note

  def apply_edit!(prev_subject, prev_body)
    additional = draft_message.additional_attributes.deep_dup
    history = Array(additional['edit_history'])
    history << {
      'at' => Time.current.iso8601,
      'operator_user_id' => user&.id,
      'prev_subject' => prev_subject,
      'prev_body' => prev_body,
      'new_subject' => subject,
      'new_body' => body,
      'learning_note' => learning_note
    }
    additional['edit_history'] = history
    additional['iteration_count'] = additional['iteration_count'].to_i + 1

    draft_message.update!(
      content: body,
      content_attributes: draft_message.content_attributes.deep_merge('email' => { 'subject' => subject }),
      additional_attributes: additional
    )
    Outreach::TranslateForAgents.call(
      message: draft_message,
      source_locale: draft_message.additional_attributes['locale']
    )
  end

  def record_learning!(prev_subject, prev_body)
    pid = draft_message.additional_attributes['campaign_participant_id']
    participant = pid ? CampaignParticipant.find_by(id: pid) : nil
    return unless participant

    OutboundCampaignLearning.create!(
      outbound_campaign: participant.outbound_campaign,
      user: user,
      draft_message: draft_message,
      source_kind: 'operator_edit',
      slot: draft_message.additional_attributes['template_slot'],
      locale: draft_message.additional_attributes['locale'],
      content: build_learning_content(prev_subject, prev_body)
    )
  end

  def build_learning_content(prev_subject, prev_body)
    parts = []
    parts << "Operator note: #{learning_note}" if learning_note
    if prev_subject != subject
      parts << "Subject change: \"#{prev_subject}\" → \"#{subject}\""
    end
    if prev_body != body
      parts << "Body changed (#{prev_body.length} → #{body.length} chars)."
      parts << "New body excerpt: #{body.truncate(280)}"
    end
    parts.join("\n")
  end
end
