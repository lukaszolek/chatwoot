class Outreach::Agent::Tools::GetRegistrationStatus < Outreach::Agent::Tools::Base
  description <<~DESC
    Checks the Framky Partner Panel for whether this photographer has
    completed registration (and when). Returns the partner code once
    issued. Use when the photographer asks 'did my signup go through?'
    or before promising commission information that requires registration.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true

  def execute!(profile:, **_params)
    raise ArgumentError, 'profile has no external_id' if profile.external_id.blank?

    Framky::PartnerProgramClient.new.registration_status(profile.external_id)
  end
end
