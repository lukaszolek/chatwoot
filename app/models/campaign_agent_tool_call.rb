# Audit log for each Outreach::Agent::Toolbox dispatch. Captures the LLM-
# supplied params, the tool's result, success/failure, and performance.
# Critical for postmortems on agent behavior and detecting prompt-injection
# attempts (e.g. LLM trying update_marketing_consent with a sender_email
# that mismatches the conversation scope — the tool refuses, this row
# records it).
# == Schema Information
#
# Table name: campaign_agent_tool_calls
#
#  id                              :bigint           not null, primary key
#  error_message                   :text
#  latency_ms                      :integer
#  model                           :string
#  params                          :jsonb            not null
#  result                          :jsonb            not null
#  success                         :boolean          default(FALSE), not null
#  tool_name                       :string           not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  conversation_id                 :bigint
#  draft_message_id                :bigint
#  photographer_partner_profile_id :bigint
#
# Indexes
#
#  idx_on_photographer_partner_profile_id_685b525488    (photographer_partner_profile_id)
#  index_campaign_agent_tool_calls_on_conversation_id   (conversation_id)
#  index_campaign_agent_tool_calls_on_draft_message_id  (draft_message_id)
#  index_campaign_agent_tool_calls_on_tool_name         (tool_name)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (draft_message_id => messages.id)
#  fk_rails_...  (photographer_partner_profile_id => photographer_partner_profiles.id)
#
class CampaignAgentToolCall < ApplicationRecord
  belongs_to :photographer_partner_profile, optional: true
  belongs_to :conversation, optional: true
  belongs_to :draft_message, class_name: 'Message', optional: true

  validates :tool_name, presence: true
end
