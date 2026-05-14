# == Schema Information
#
# Table name: campaign_pipeline_stages
#
#  id                       :bigint           not null, primary key
#  auto_advance_after_hours :integer
#  branch_rules             :jsonb            not null
#  key                      :string           not null
#  next_stage_key           :string
#  on_enter_action          :integer          not null
#  position                 :integer          not null
#  template_slot            :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  outbound_campaign_id     :bigint           not null
#
# Indexes
#
#  idx_pipeline_stages_campaign_key                        (outbound_campaign_id,key) UNIQUE
#  idx_pipeline_stages_campaign_position                   (outbound_campaign_id,position)
#  index_campaign_pipeline_stages_on_outbound_campaign_id  (outbound_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (outbound_campaign_id => outbound_campaigns.id) ON DELETE => cascade
#
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
