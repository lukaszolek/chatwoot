# Marks an outreach draft as discarded — soft-delete without escalating the
# participant. Used when an operator manually deletes the draft, or when a
# newer reply (incoming from contact or outgoing from another channel such as
# Gmail) makes the draft stale.
class Outreach::Drafts::DiscardService
  class Error < StandardError; end

  def initialize(draft_message:, user: nil, reason: nil)
    @draft_message = draft_message
    @user = user
    @reason = reason.to_s.strip.presence
  end

  def call
    raise Error, 'not an outreach draft' unless draft_message.outreach_draft?
    raise Error, "draft already #{draft_message.outreach_draft_status}" \
      unless draft_message.outreach_draft_status == 'pending'

    draft_message.update!(
      additional_attributes: draft_message.additional_attributes.merge(
        'draft_status' => 'discarded',
        'discarded_by_user_id' => user&.id,
        'discarded_at' => Time.current.iso8601,
        'discarded_reason' => reason
      )
    )
    { ok: true }
  end

  private

  attr_reader :draft_message, :user, :reason
end
