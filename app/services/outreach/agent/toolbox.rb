# Builds a set of RubyLLM::Tool instances scoped to a single inbound
# email's sender. The LLM gets the tool list to call mid-turn (via
# `chat.with_tool(t)` in Outreach::Llm::Client#ask_with_tools!) but every
# tool re-checks the sender_email parameter against the toolbox-scoped
# value before doing anything. Mismatch → tool returns
# {error: 'forbidden'} and writes a CampaignAgentToolCall row with
# success: false. Even if the LLM hallucinates someone else's email in
# the tool call args, the tool refuses.
#
# Usage:
#   toolbox = Outreach::Agent::Toolbox.new(
#     scoped_sender_email: incoming.from_email,
#     account: account, conversation: convo, draft_message: nil
#   )
#   client.ask_with_tools!(model:, system:, user:, tools: toolbox.tools)
class Outreach::Agent::Toolbox
  attr_reader :scoped_sender_email, :account, :conversation, :draft_message

  TOOL_CLASSES = [
    Outreach::Agent::Tools::ReadPhotographerProfile,
    Outreach::Agent::Tools::UpdateMarketingConsent,
    Outreach::Agent::Tools::SetPartnershipStatus,
    Outreach::Agent::Tools::AddInternalNote,
    Outreach::Agent::Tools::GetRegistrationStatus,
    Outreach::Agent::Tools::GetCommissionBalance,
    Outreach::Agent::Tools::SubmitInvoice,
    Outreach::Agent::Tools::EscalateToOperator
  ].freeze

  def initialize(scoped_sender_email:, account:, conversation: nil, draft_message: nil)
    raise ArgumentError, 'scoped_sender_email is required' if scoped_sender_email.blank?

    @scoped_sender_email = scoped_sender_email.to_s.downcase
    @account = account
    @conversation = conversation
    @draft_message = draft_message
  end

  def tools
    TOOL_CLASSES.map { |klass| klass.new(toolbox: self) }
  end

  # Profile lookup the tools share. Nil when the sender isn't a known
  # photographer in this account; tools refuse with 'unknown_sender'.
  def scoped_profile
    @scoped_profile ||= PhotographerPartnerProfile.find_by(
      account_id: account.id, email: scoped_sender_email
    )
  end

  # Guard used by every tool. Returns the scoped profile when the LLM-
  # supplied email matches, raises ToolAuthorizationError otherwise.
  def scope_to_sender!(sender_email)
    raise ToolAuthorizationError, 'sender_email_mismatch' \
      unless sender_email.to_s.downcase == scoped_sender_email
    raise ToolAuthorizationError, 'unknown_sender' if scoped_profile.nil?

    scoped_profile
  end

  def log!(tool_name:, params:, result:, success:, error_message: nil, latency_ms: nil)
    CampaignAgentToolCall.create!(
      photographer_partner_profile_id: scoped_profile&.id,
      conversation_id: conversation&.id,
      draft_message_id: draft_message&.id,
      tool_name: tool_name.to_s,
      params: params.is_a?(Hash) ? params : {},
      result: result.is_a?(Hash) ? result : { value: result },
      success: success,
      error_message: error_message,
      latency_ms: latency_ms
    )
  rescue StandardError => e
    Rails.logger.warn("[outreach.toolbox] failed_to_log: #{e.class}: #{e.message}")
  end

  class ToolAuthorizationError < StandardError; end
end
