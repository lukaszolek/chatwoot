# RFC 8058 one-click unsubscribe endpoint for outreach emails.
#
#   GET  /unsubscribe/:token  -> renders a confirmation page (human click)
#   POST /unsubscribe/:token  -> one-click (List-Unsubscribe-Post) — body
#                                'List-Unsubscribe=One-Click' is accepted
#                                but not required
#
# Token authenticates + identifies the participant; no login required.
# Opt-out cascades: profile -> all participants for that profile ->
# photographer-directory (via Outreach::PhotographerDirectory::ConsentWriter
# async). A single attribution event is written for audit.
#
# Public controller, no CSRF check on POST because the token itself is
# the credential (RFC 8058 POSTs come from mail providers, not browsers
# with our session cookies).
class Outreach::UnsubscribesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  skip_before_action :verify_authenticity_token, only: [:one_click]

  def show
    process_unsubscribe_for(params[:token])
    render 'outreach/unsubscribes/show', status: :ok
  rescue Outreach::UnsubscribeToken::InvalidToken
    render plain: 'Invalid or expired unsubscribe link.', status: :not_found
  end

  def one_click
    process_unsubscribe_for(params[:token])
    head :ok
  rescue Outreach::UnsubscribeToken::InvalidToken
    head :not_found
  end

  private

  def process_unsubscribe_for(token)
    decoded = Outreach::UnsubscribeToken.verify(token)
    participant = CampaignParticipant.find_by(id: decoded[:participant_id])
    return unless participant

    profile = participant.participatable
    return unless profile.is_a?(PhotographerPartnerProfile)

    apply_opt_out(profile)
  end

  def apply_opt_out(profile)
    ActiveRecord::Base.transaction do
      profile.transition_to!(:do_not_contact) unless profile.do_not_contact?
      CampaignParticipant.where(participatable: profile).where(paused: false).update_all( # rubocop:disable Rails/SkipsModelValidations
        paused: true, updated_at: Time.current
      )
    end

    Outreach::PhotographerDirectory::PropagateConsentJob
      .perform_later(profile.id, 'opt_out', reason: 'list_unsubscribe')
  end
end
