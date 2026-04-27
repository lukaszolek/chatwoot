class Outreach::Agent::Tools::SetPartnershipStatus < Outreach::Agent::Tools::Base
  ALLOWED_STATUSES = %w[
    qualified contacted replied interested signed_up declined do_not_contact completed
  ].freeze

  description <<~DESC
    Moves the photographer's partnership pipeline status. Use sparingly —
    typically only when the photographer's reply makes a transition
    obvious (e.g. they confirm they signed up → 'signed_up'; they ask to
    be removed → 'do_not_contact'). The sender_email MUST match.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true
  param :status, desc: "One of: #{ALLOWED_STATUSES.join(', ')}", required: true
  param :reason, desc: 'Short freeform note explaining why', required: true

  def execute!(profile:, status:, reason:, **_params)
    raise ArgumentError, "invalid status '#{status}' (allowed: #{ALLOWED_STATUSES.join(', ')})" \
      unless ALLOWED_STATUSES.include?(status.to_s)

    profile.transition_to!(status.to_s)
    { ok: true, partnership_status: profile.reload.partnership_status, reason_recorded: reason.truncate(180) }
  end
end
