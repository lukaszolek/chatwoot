# Single call site for writing CampaignLlmDecision rows. Every LLM
# invocation (compose, classify, draft) goes through this so the audit
# trail has a consistent shape, including token usage, latency, and
# input_digest (SHA-256 of the prompt payload, so duplicate calls are
# discoverable).
class Outreach::Llm::DecisionLogger
  # rubocop:disable Metrics/ParameterLists
  def self.record!(participant:, decision_type:, input:, output:, model:, prompt_version:,
                   confidence: nil, routed_to: nil, token_usage: {}, latency_ms: nil)
    CampaignLlmDecision.create!(
      campaign_participant: participant,
      outbound_campaign: participant.outbound_campaign,
      conversation: participant.conversation,
      decision_type: decision_type,
      model: model,
      prompt_version: prompt_version,
      input_digest: Digest::SHA256.hexdigest(input.to_s),
      output: output,
      confidence: confidence,
      routed_to: routed_to,
      token_usage: token_usage || {},
      latency_ms: latency_ms
    )
  end
  # rubocop:enable Metrics/ParameterLists
end
