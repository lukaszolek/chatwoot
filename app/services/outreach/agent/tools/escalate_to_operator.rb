# A self-eject hatch for the LLM. When the conversation crosses into a
# domain the model isn't equipped to handle (legal questions, refund
# disputes, anything sensitive), it calls this and the Reply composer
# treats the entire message as escalate=true so a human picks it up.
class Outreach::Agent::Tools::EscalateToOperator < Outreach::Agent::Tools::Base
  description <<~DESC
    Hands the conversation to a human operator. Use when you cannot or
    should not answer (legal/refund disputes, complex tax questions,
    anything you'd rather a human verify). The reason is shown to the
    operator who picks it up.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true
  param :reason, desc: 'One-sentence reason for escalation', required: true

  def execute!(reason:, **_params)
    { ok: true, escalated: true, reason: reason.to_s.truncate(280) }
  end
end
