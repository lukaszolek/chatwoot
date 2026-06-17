class Api::V1::Accounts::Outreach::CampaignsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :campaign, except: [:index]

  def index
    @campaigns = Current.account.outbound_campaigns.order(:name)
  end

  def show; end

  def update
    @campaign.update!(campaign_params)
    render :show
  end

  def pause
    @campaign.update!(status: :paused)
    render :show
  end

  def resume
    @campaign.update!(status: :active)
    render :show
  end

  def archive
    @campaign.update!(status: :archived)
    render :show
  end

  def retry_generation
    Outreach::Engine::GenerationRetry.new(participant).call
    render json: { ok: true }, status: :ok
  end

  def mark_not_relevant
    ActiveRecord::Base.transaction do
      discard_pending_outreach_drafts!(
        participant.conversation,
        reason: 'operator_mark_not_relevant'
      )
      mark_participant_not_relevant!
      profile.transition_to!(:declined) if profile.is_a?(PhotographerPartnerProfile) && !profile.declined?
    end
    render json: { ok: true }, status: :ok
  end

  private

  def campaign
    @campaign ||= Current.account.outbound_campaigns.find(params[:id])
  end

  def participant
    @participant ||= @campaign.participants.find(params[:participant_id])
  end

  def profile
    @profile ||= participant.participatable
  end

  def campaign_params
    params.require(:outbound_campaign).permit(:inbox_id, :sender_user_id, :manual_review_mode)
  end

  def check_authorization
    authorize(OutboundCampaign)
  end

  def discard_pending_outreach_drafts!(conversation, reason:)
    return unless conversation

    Outreach::Drafts::DiscardPendingConversationDraftsService.new(
      conversation: conversation,
      user: Current.user,
      reason: reason
    ).call
  end

  def mark_participant_not_relevant!
    participant.update!(
      paused: true,
      next_action_at: nil,
      metadata: participant.metadata.to_h.except(
        'last_error',
        'last_error_at',
        'processing_started_at'
      ).merge(
        'paused_reason' => 'operator_marked_not_relevant',
        'not_relevant_at' => Time.current.iso8601,
        'not_relevant_by_user_id' => Current.user&.id
      )
    )
  end
end
