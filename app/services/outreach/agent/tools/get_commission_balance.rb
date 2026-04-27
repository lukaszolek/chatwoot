class Outreach::Agent::Tools::GetCommissionBalance < Outreach::Agent::Tools::Base
  description <<~DESC
    Reads the photographer's current pending and payable commission
    balance from the Framky Partner Panel backend. Use when the
    photographer asks about earnings, payouts, or thresholds. Numbers
    are authoritative — do NOT make them up; if the tool returns
    not_implemented_yet, tell the photographer you'll have an operator
    confirm and stop.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true

  def execute!(profile:, **_params)
    raise ArgumentError, 'profile has no external_id' if profile.external_id.blank?

    Framky::PartnerProgramClient.new.commission_balance(profile.external_id)
  end
end
