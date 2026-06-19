class Outreach::CompareDraftModelsJob < ApplicationJob
  queue_as :outreach_interactive

  def perform(draft_message_id:, models: nil, operator_prompt: nil)
    draft_message = Message.find(draft_message_id)
    Outreach::Drafts::CompareModelsService.new(
      draft_message: draft_message,
      models: models.presence || Outreach::Drafts::CompareModelsService.default_models,
      operator_prompt: operator_prompt
    ).call
  rescue StandardError => e
    Rails.logger.warn(
      "[outreach.drafts.compare_models] draft=#{draft_message_id} error=#{e.class}: #{e.message.to_s.truncate(200)}"
    )
  end
end
