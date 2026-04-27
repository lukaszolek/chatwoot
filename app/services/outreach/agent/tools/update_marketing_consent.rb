# Flips the photographer's tri-state consent. 'declined' triggers the
# photographer-directory propagation job (so the upstream secondary DB
# stays in sync) — see Outreach::PhotographerDirectory::ConsentWriter.
class Outreach::Agent::Tools::UpdateMarketingConsent < Outreach::Agent::Tools::Base
  description <<~DESC
    Records the photographer's marketing-consent decision. Use 'granted'
    when they explicitly opted in, 'declined' when they asked us to stop
    contacting them. The sender_email MUST match the inbound message's
    From address.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true
  param :state, desc: "One of: 'granted' | 'declined'", required: true
  param :reason, desc: 'Short freeform note explaining why', required: true

  def execute!(profile:, state:, reason:, **_params)
    raise ArgumentError, "invalid state '#{state}' (allowed: granted|declined)" \
      unless %w[granted declined].include?(state.to_s)

    profile.update!(marketing_consent_state: state)

    if state.to_s == 'declined' && defined?(Outreach::PhotographerDirectory::PropagateConsentJob)
      Outreach::PhotographerDirectory::PropagateConsentJob.perform_later(
        profile.id, 'opt_out', reason: "agent_tool: #{reason.truncate(180)}"
      )
    end

    { ok: true, profile_id: profile.id, marketing_consent_state: profile.reload.marketing_consent_state }
  end
end
