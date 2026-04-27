# Audit log for each Outreach::Agent::Toolbox dispatch. Captures the LLM-
# supplied params, the tool's result, success/failure, and performance.
# Critical for postmortems on agent behavior and detecting prompt-injection
# attempts (e.g. LLM trying update_marketing_consent with a sender_email
# that mismatches the conversation scope — the tool refuses, this row
# records it).
class CampaignAgentToolCall < ApplicationRecord
  belongs_to :photographer_partner_profile, optional: true
  belongs_to :conversation, optional: true
  belongs_to :draft_message, class_name: 'Message', optional: true

  validates :tool_name, presence: true
end
