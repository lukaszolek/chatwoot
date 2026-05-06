# ClassifyReply executor: calls the LLM reply classifier, writes a
# CampaignLlmDecision row, and applies branch_rules based on intent
# class + confidence.
#
# Branch outcome rules (resolved here, not in data):
#   - No matching rule for intent_class ............... escalate
#   - confidence >= rule.min_confidence ............... follow rule.target
#                                                       (auto-compose reply)
#   - rule.min_confidence > confidence >= 0.5 ......... compose reply (draft if
#                                                       manual_review_mode, autopilot otherwise)
#   - confidence < 0.5 ................................ escalate
#
# When the rule resolves to a `reply` action — and the intent_class is
# something we can answer (interested_commission, asks_product, asks_showroom,
# unclear-but-mid-confidence) — we instantiate a Reply composer with the
# scoped Toolbox (sender's email is the inbound message's From) and
# generate a body. If the composer escalates (LLM called
# escalate_to_operator, or fell through fallback) we route to escalated.
class Outreach::Engine::Executors::ClassifyReply < Outreach::Engine::Executors::Base
  ESCALATED_STAGE_KEY = 'escalated'.freeze
  SIGNUP_INTENT = 'interested_signup'.freeze
  MIN_DRAFT_CONFIDENCE = 0.5
  DECLINE_PROPAGATION_CONFIDENCE = 0.85

  def call
    outcome = classifier_outcome
    decision = record_decision(outcome)
    propagate_decline_if_applicable(outcome)
    update_partnership_status_from_intent!(outcome)
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
    return :operator_draft if signup_intent?(outcome) && outcome[:confidence].to_f >= MIN_DRAFT_CONFIDENCE

    rule = branch_rule_for(outcome[:intent_class])
    return :escalate if rule.nil? || outcome[:confidence].to_f < MIN_DRAFT_CONFIDENCE

    passes_confidence = outcome[:confidence].to_f >= rule.fetch('min_confidence').to_f
    return :escalate if rule['target'] == ESCALATED_STAGE_KEY && passes_confidence
    return :auto_send if passes_confidence

    :operator_draft
  end

  # Even when the classifier routes to :escalate (e.g. interested_signup
  # is policy-escalated by branch_rules), we still want a Reply-composer
  # draft as a starting point for the human operator — IF the intent is
  # answerable. Operator opens the conversation and sees both: the
  # escalation flag + a suggested reply they can edit/regenerate/send.
  ANSWERABLE_INTENTS = %w[
    interested_signup
    interested_commission
    asks_product
    asks_showroom
    unclear
  ].freeze

  def route_to!(outcome, decision)
    routed = decision.routed_to.to_sym
    intent = outcome[:intent_class].to_s
    answerable = ANSWERABLE_INTENTS.include?(intent) && participant.conversation

    if routed == :auto_send && !campaign.manual_review_mode?
      send_reply_immediately!(outcome)
      return
    end

    # manual_review_mode is on (or routed isn't auto_send): we want a
    # draft. Compose one whenever the intent is answerable; the routing
    # decides what happens to the participant *stage*.
    compose_reply_draft!(outcome) if answerable

    case routed
    when :auto_send, :operator_draft
      park_for_operator!
    else # :escalate or anything we don't recognise
      escalate!(reason: escalation_reason(outcome))
    end
  end

  def compose_reply_draft!(outcome)
    sender_email = inbound_sender_email
    return Rails.logger.warn('[outreach.classify_reply] no inbound') unless inbound_message
    return Rails.logger.warn('[outreach.classify_reply] sender mismatch') if sender_email_mismatch?(sender_email)

    composed = compose_reply(sender_email, outcome: outcome)
    if composed[:escalate]
      Rails.logger.info("[outreach.classify_reply] reply composer self-escalated: #{composed[:reason]}")
      return
    end

    create_outreach_draft_message!(composed)
  end

  def send_reply_immediately!(outcome)
    sender_email = inbound_sender_email
    return escalate!(reason: 'reply_composer_no_inbound') unless inbound_message
    return escalate!(reason: 'reply_composer_sender_mismatch') if sender_email_mismatch?(sender_email)

    composed = compose_reply(sender_email, outcome: outcome)
    return escalate!(reason: "reply_composer_escalate:#{composed[:reason]}") if composed[:escalate]

    send_immediately!(outcome, composed)
  end

  # Same role as SendTemplate#park_for_operator! — drop next_action_at
  # so the runner stops re-classifying / re-composing this reply on
  # every tick while the draft is pending.
  def park_for_operator!
    metadata = (participant.metadata || {}).merge('parked_for_operator_at' => Time.current.iso8601)
    participant.update!(next_action_at: nil, metadata: metadata)
  end

  def compose_reply(sender_email, outcome: nil)
    toolbox = Outreach::Agent::Toolbox.new(
      scoped_sender_email: sender_email,
      account: participant.account,
      conversation: participant.conversation
    )
    Outreach::Llm::MessageComposer::Reply.new(
      participant: participant,
      conversation: participant.conversation,
      toolbox: toolbox,
      operator_hint: reply_operator_hint(outcome)
    ).call
  end

  def create_outreach_draft_message!(composed)
    participant.conversation.messages.create!(
      account: participant.conversation.account,
      inbox: participant.conversation.inbox,
      message_type: :outgoing,
      private: true,
      sender: campaign.sender_user,
      content: composed[:body],
      content_type: 'text',
      content_attributes: { email: { subject: composed[:subject] } },
      additional_attributes: {
        'outreach_draft' => true,
        'draft_status' => 'pending',
        'template_slot' => 'reply',
        'locale' => composed[:locale],
        'composer_model' => composed[:model],
        'composer_prompt_version' => composed[:prompt_version],
        'composer_input_digest' => composed[:input_digest],
        'iteration_count' => 1,
        'regeneration_history' => [],
        'campaign_participant_id' => participant.id,
        'outbound_campaign_id' => campaign.id,
        'tool_calls' => composed[:tool_calls] || []
      }
    )
  end

  def reply_operator_hint(outcome)
    return nil unless signup_intent?(outcome)

    <<~TEXT.squish
      The photographer appears ready to join or asks for the registration link.
      Use the campaign knowledge document kind=reply_signup for tone and required details.
      If the inbound message is a simple confirmation, send a short reply with the registration link.
      If the inbound message includes questions or concerns, answer them briefly first, then include the registration link as the next step when appropriate.
      Do not escalate only because the photographer wants to sign up.
    TEXT
  end

  def signup_intent?(outcome)
    outcome[:intent_class].to_s == SIGNUP_INTENT
  end

  def send_immediately!(outcome, composed)
    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: participant.conversation.id,
      subject: composed[:subject],
      body: composed[:body],
      template_slot: 'reply',
      locale: composed[:locale]
    )
    rule = branch_rule_for(outcome[:intent_class])
    target = rule&.dig('target') || ESCALATED_STAGE_KEY
    transition_to!(target)
  end

  def inbound_message
    return nil unless participant.conversation

    participant.conversation.messages
               .where(message_type: :incoming, private: false)
               .order(created_at: :desc)
               .first
  end

  def inbound_sender_email
    msg = inbound_message
    msg&.content_attributes&.dig('email', 'from')&.first ||
      msg&.sender&.try(:email) ||
      participant.participatable.email
  end

  def sender_email_mismatch?(sender_email)
    sender_email.to_s.downcase != participant.participatable.email.to_s.downcase
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

  # Promote profile.partnership_status based on classified intent so the
  # Outreach → Pipeline view (which keys off partnership_status) reflects
  # reality. Conservative — never overwrite a stronger commitment
  # (signed_up / completed / do_not_contact / declined). Only bumps the
  # photographer up the funnel.
  STATUS_BUMP_BY_INTENT = {
    'interested_signup' => :interested,
    'interested_commission' => :interested,
    'asks_product' => :interested,
    'asks_showroom' => :interested,
    'declined' => :declined
  }.freeze

  STATUS_RANK = {
    nil => 0,
    'imported' => 0,
    'qualified' => 1,
    'contacted' => 2,
    'replied' => 3,
    'interested' => 4,
    'signed_up' => 5,
    'completed' => 6,
    'declined' => 99,   # terminal — never overwrite
    'do_not_contact' => 99    # terminal — never overwrite
  }.freeze

  def update_partnership_status_from_intent!(outcome)
    target = STATUS_BUMP_BY_INTENT[outcome[:intent_class].to_s]
    return unless target
    return if outcome[:confidence].to_f < MIN_DRAFT_CONFIDENCE

    profile = participant.participatable
    return unless profile.is_a?(PhotographerPartnerProfile)

    current_rank = STATUS_RANK[profile.partnership_status.to_s] || 0
    target_rank  = STATUS_RANK[target.to_s] || 0
    return if current_rank >= target_rank && target.to_s != 'declined'
    return if profile.partnership_status.to_s == 'declined' || profile.partnership_status.to_s == 'do_not_contact'

    profile.transition_to!(target)
    Rails.logger.info(
      "[outreach.classify_reply] status_bump participant=#{participant.id} " \
      "from=#{profile.partnership_status_was} to=#{target} intent=#{outcome[:intent_class]}"
    )
  rescue StandardError => e
    Rails.logger.warn("[outreach.classify_reply] status bump failed: #{e.class}: #{e.message}")
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
