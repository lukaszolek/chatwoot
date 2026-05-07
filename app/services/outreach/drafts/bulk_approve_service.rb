class Outreach::Drafts::BulkApproveService
  Result = Struct.new(:requested, :selected, :approved, :failed, :errors, keyword_init: true)
  DEFAULT_TEMPLATE_SLOT = 'intro'.freeze

  def initialize(campaign:, user:, limit:, template_slot: DEFAULT_TEMPLATE_SLOT)
    @campaign = campaign
    @user = user
    @limit = limit
    @template_slot = template_slot.presence || DEFAULT_TEMPLATE_SLOT
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

  attr_reader :campaign, :user, :limit, :template_slot

  def drafts
    @drafts ||= Message.pending_outreach_drafts
                       .joins(:conversation)
                       .where(conversations: { account_id: campaign.account_id })
                       .where("messages.additional_attributes->>'outbound_campaign_id' = ?", campaign.id.to_s)
                       .where("messages.additional_attributes->>'template_slot' = ?", template_slot)
                       .order(:created_at, :id)
                       .limit(limit)
                       .to_a
  end
end
