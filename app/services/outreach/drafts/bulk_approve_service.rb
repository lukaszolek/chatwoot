class Outreach::Drafts::BulkApproveService
  Result = Struct.new(:requested, :selected, :approved, :failed, :errors, keyword_init: true)

  def initialize(campaign:, user:, limit:)
    @campaign = campaign
    @user = user
    @limit = limit
  end

  def call
    result = Result.new(requested: limit, selected: drafts.size, approved: 0, failed: 0, errors: [])

    drafts.each do |draft|
      Outreach::Drafts::ApproveService.new(draft_message: draft, user: user).call
      result.approved += 1
    rescue StandardError => e
      result.failed += 1
      result.errors << { draft_message_id: draft.id, message: "#{e.class}: #{e.message}" }
    end

    result
  end

  private

  attr_reader :campaign, :user, :limit

  def drafts
    @drafts ||= Message.pending_outreach_drafts
                       .joins(:conversation)
                       .where(conversations: { account_id: campaign.account_id, status: :open })
                       .where("messages.additional_attributes->>'outbound_campaign_id' = ?", campaign.id.to_s)
                       .order(:created_at, :id)
                       .limit(limit)
                       .to_a
  end
end
