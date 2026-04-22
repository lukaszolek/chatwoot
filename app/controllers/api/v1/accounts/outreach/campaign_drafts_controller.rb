class Api::V1::Accounts::Outreach::CampaignDraftsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :draft, except: [:index]

  PER_PAGE = 50

  def index
    scope = CampaignDraft.joins(:campaign_participant)
                         .where(campaign_participants: { account_id: Current.account.id })
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.pending_review if params[:status].blank?
    @drafts = scope.order(created_at: :asc).limit(PER_PAGE).offset(((params[:page] || 1).to_i - 1) * PER_PAGE)
  end

  def show; end

  def update
    @draft.update!(draft_params.merge(iteration_count: (@draft.iteration_count || 0) + 1))
    render :show
  end

  def approve
    return render(json: { error: "Draft is already #{@draft.status}" }, status: :conflict) unless @draft.pending_review?

    send_draft!
    render :show
  end

  def reject
    return render(json: { error: "Draft is already #{@draft.status}" }, status: :conflict) unless @draft.pending_review?

    @draft.update!(status: :rejected, reviewed_at: Time.current, reviewed_by_user: Current.user)
    escalate_participant!(@draft.campaign_participant)
    render :show
  end

  private

  def send_draft!
    participant = @draft.campaign_participant
    conversation = participant.conversation

    Outreach::SendEmailJob.perform_later(
      participant_id: participant.id,
      conversation_id: conversation.id,
      subject: @draft.subject,
      body: @draft.body,
      template_slot: @draft.template_slot,
      locale: @draft.locale
    )

    @draft.update!(status: :sent, reviewed_at: Time.current, reviewed_by_user: Current.user)
    participant.update!(current_stage_key: 'terminal', stage_entered_at: Time.current, paused: true)
  end

  def escalate_participant!(participant)
    return if participant.paused?

    participant.update!(
      current_stage_key: 'escalated',
      stage_entered_at: Time.current,
      next_action_at: Time.current
    )
  end

  def draft
    @draft ||= CampaignDraft.joins(:campaign_participant)
                            .where(campaign_participants: { account_id: Current.account.id })
                            .find(params[:id])
  end

  def draft_params
    params.require(:campaign_draft).permit(:subject, :body)
  end

  def check_authorization
    authorize(CampaignDraft)
  end
end
