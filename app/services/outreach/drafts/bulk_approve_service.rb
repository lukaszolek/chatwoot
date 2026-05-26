class Outreach::Drafts::BulkApproveService
  Result = Struct.new(:requested, :selected, :approved, :failed, :errors, :template_slot, keyword_init: true)
  DEFAULT_TEMPLATE_SLOT = 'intro'.freeze

  def initialize(campaign:, user:, limit:, template_slot: DEFAULT_TEMPLATE_SLOT)
    @campaign = campaign
    @user = user
    @limit = limit
    @template_slot = template_slot.presence || DEFAULT_TEMPLATE_SLOT
  end

  def call
    result = Result.new(
      requested: limit,
      selected: drafts.size,
      approved: 0,
      failed: 0,
      errors: [],
      template_slot: template_slot
    )

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
    @drafts ||= begin
      scope = Message.pending_outreach_drafts
                     .joins(:conversation)
                     .where(conversations: { account_id: campaign.account_id })
                     .where("messages.additional_attributes->>'outbound_campaign_id' = ?", campaign.id.to_s)
                     .where("messages.additional_attributes->>'template_slot' = ?", template_slot)

      scope = restrict_to_followup_enabled_locales(scope) if followup_template_slot?

      scope.order(:created_at, :id).limit(limit).to_a
    end
  end

  def followup_template_slot?
    %w[reminder breakup].include?(template_slot.to_s)
  end

  def restrict_to_followup_enabled_locales(scope)
    return scope.none if enabled_followup_locales.blank?

    scope.where("LOWER(messages.additional_attributes->>'locale') IN (?)", enabled_followup_locales)
  end

  def enabled_followup_locales
    configured = (campaign.config || {})['followup_enabled_locales']
    enabled = configured.presence ||
              Outreach::Engine::Executors::SendTemplate::DEFAULT_FOLLOWUP_ENABLED_LOCALES[campaign.program_key]
    Array(enabled).map { |locale| locale.to_s.downcase }
  end
end
