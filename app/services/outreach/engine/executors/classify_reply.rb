# ClassifyReply executor: calls the LLM reply classifier, writes a
# CampaignLlmDecision row, and applies branch_rules based on intent
# class + confidence.
#
# Branch outcome rules (resolved here, not in data):
#   - No matching rule for intent_class ............... escalate
#   - confidence >= rule.min_confidence ............... follow rule.target (auto_send)
#   - rule.min_confidence > confidence >= 0.5 ......... create operator draft
#   - confidence < 0.5 ................................ escalate
#
# In C3.1 the draft creation path is not fully wired — the real subject
# and body come from Outreach::Llm::DraftReplyComposer (C4.1). When a
# draft would be created but the composer is not yet available, we fall
# back to escalation so the operator still sees the conversation.
class Outreach::Engine::Executors::ClassifyReply < Outreach::Engine::Executors::Base
  ESCALATED_STAGE_KEY = 'escalated'.freeze
  MIN_DRAFT_CONFIDENCE = 0.5
  DECLINE_PROPAGATION_CONFIDENCE = 0.85

  def call
    outcome = classifier_outcome
    decision = record_decision(outcome)
    propagate_decline_if_applicable(outcome)
    route_to!(outcome, decision)
  end

  private

  def classifier_outcome
    Outreach::Llm::ReplyClassifier.new(
      participant: participant,
      conversation: participant.conversation,
      locale: participant_locale
    ).call
  end

  def record_decision(outcome)
    routed_to = resolve_routed_to(outcome)
    Outreach::Llm::DecisionLogger.record!(
      participant: participant,
      decision_type: :classify_reply,
      input: outcome[:input_digest] || outcome.fetch(:output, {}).to_json,
      output: outcome.fetch(:output, {}),
      model: outcome.fetch(:model),
      prompt_version: outcome[:prompt_version],
      confidence: outcome[:confidence],
      routed_to: routed_to,
      token_usage: outcome[:token_usage],
      latency_ms: outcome[:latency_ms]
    )
  end

  def resolve_routed_to(outcome)
    rule = branch_rule_for(outcome[:intent_class])
    return :escalate if rule.nil? || outcome[:confidence].to_f < MIN_DRAFT_CONFIDENCE

    passes_confidence = outcome[:confidence].to_f >= rule.fetch('min_confidence').to_f
    return :escalate if rule['target'] == ESCALATED_STAGE_KEY && passes_confidence
    return :auto_send if passes_confidence

    :operator_draft
  end

  def route_to!(outcome, decision)
    case decision.routed_to.to_sym
    when :auto_send
      transition_to!(branch_rule_for(outcome[:intent_class]).fetch('target'))
    when :operator_draft
      # C4.1 / C6.1 will compose a real draft via Outreach::Llm::DraftReplyComposer.
      # Until then we fall back to escalation to guarantee operator visibility.
      escalate!(reason: "operator_draft_pending_llm:#{outcome[:intent_class]}")
    else
      escalate!(reason: escalation_reason(outcome))
    end
  end

  def escalation_reason(outcome)
    rule = branch_rule_for(outcome[:intent_class])
    return "unknown_intent:#{outcome[:intent_class] || 'nil'}" if rule.nil?
    return "explicit_escalate:#{outcome[:intent_class]}" if rule['target'] == ESCALATED_STAGE_KEY

    "classifier_low_confidence:#{outcome[:intent_class]}"
  end

  def branch_rule_for(intent_class)
    return nil if intent_class.nil?

    rules = stage.branch_rules || {}
    rules[intent_class.to_s] || rules[intent_class.to_sym.to_s]
  end

  def escalate!(reason:)
    metadata = (participant.metadata || {}).merge('escalation_reason' => reason)
    participant.update!(metadata: metadata)
    transition_to!(ESCALATED_STAGE_KEY)
  end

  def propagate_decline_if_applicable(outcome)
    return unless outcome[:intent_class] == 'declined'
    return if outcome[:confidence].to_f < DECLINE_PROPAGATION_CONFIDENCE

    profile = participant.participatable
    return unless profile.is_a?(PhotographerPartnerProfile)

    Outreach::PhotographerDirectory::PropagateConsentJob
      .perform_later(profile.id, 'opt_out', reason: 'explicit_decline')
  end

  def participant_locale
    (participant.metadata || {})['locale'].presence ||
      participant.participatable.try(:preferred_language).presence ||
      (campaign.config || {})['default_locale'].presence ||
      'en'
  end
end
