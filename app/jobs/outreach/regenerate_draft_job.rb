class Outreach::RegenerateDraftJob < ApplicationJob
  queue_as :outreach

  def perform(draft_message_id:, user_id:, operator_prompt:)
    draft_message = Message.find(draft_message_id)
    user = User.find_by(id: user_id)

    mark_regeneration!(draft_message, 'processing')
    Outreach::Drafts::RegenerateService.new(
      draft_message: draft_message,
      user: user,
      operator_prompt: operator_prompt
    ).call
    mark_regeneration!(draft_message.reload, nil)
  rescue StandardError => e
    mark_failed!(draft_message_id, e)
  end

  private

  def mark_regeneration!(draft_message, status, error = nil)
    additional = draft_message.additional_attributes.to_h.deep_dup
    additional['regeneration_status'] = status
    additional['regeneration_error'] = error
    additional['regeneration_updated_at'] = Time.current.iso8601
    additional.delete('regeneration_status') if status.nil?
    additional.delete('regeneration_error') if error.nil?
    draft_message.update!(additional_attributes: additional)
  end

  def mark_failed!(draft_message_id, error)
    draft_message = Message.find_by(id: draft_message_id)
    return unless draft_message

    mark_regeneration!(
      draft_message,
      'failed',
      "#{error.class}: #{error.message}".truncate(500)
    )
  end
end
