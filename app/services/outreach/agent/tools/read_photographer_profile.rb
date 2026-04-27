class Outreach::Agent::Tools::ReadPhotographerProfile < Outreach::Agent::Tools::Base
  description <<~DESC
    Returns the requesting photographer's profile fields (email, business name,
    owner name, country, locale, marketing consent state, partnership status,
    last sync). Use this to check what we already know before answering.
    The sender_email parameter MUST match the email of the message you are
    replying to — the tool refuses any other address.
  DESC

  param :sender_email, desc: 'Email address of the photographer who sent the inbound message', required: true

  def execute!(profile:, **_params)
    {
      email: profile.email,
      business_name: profile.business_name,
      owner_name: profile.owner_name,
      country_code: profile.country_code,
      locale: profile.preferred_language,
      instagram_handle: profile.instagram_handle,
      website: profile.website,
      marketing_consent_state: profile.marketing_consent_state,
      partnership_status: profile.partnership_status,
      last_synced_at: profile.last_synced_at&.iso8601
    }
  end
end
