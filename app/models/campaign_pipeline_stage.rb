class CampaignPipelineStage < ApplicationRecord
  belongs_to :outbound_campaign

  enum :on_enter_action, {
    send_template: 0,
    wait: 1,
    classify_reply: 2,
    escalate_to_user: 3,
    terminal: 4
  }

  validates :key, presence: true, uniqueness: { scope: :outbound_campaign_id }
  validates :position, presence: true
  validates :on_enter_action, presence: true
  validate :template_slot_present_when_send_template
  validate :next_stage_key_exists_in_campaign

  private

  def template_slot_present_when_send_template
    return unless send_template?
    return if template_slot.present?

    errors.add(:template_slot, 'must be present for send_template stages')
  end

  def next_stage_key_exists_in_campaign
    return if next_stage_key.blank?
    return unless outbound_campaign

    sibling_keys = outbound_campaign.pipeline_stages.where.not(id: id).pluck(:key)
    return if sibling_keys.include?(next_stage_key)

    errors.add(:next_stage_key, "refers to unknown stage '#{next_stage_key}' in this campaign")
  end
end
