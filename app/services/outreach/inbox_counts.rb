class Outreach::InboxCounts
  PROGRAM_KEY = 'photographer_partnership'.freeze

  QUEUES = {
    action_needed: { status: 'open', label: 'outreach_replied' },
    drafts: { status: 'open', label: 'outreach_draft' },
    sent: { status: 'pending', label: 'outreach_sent' },
    bounced: { status: 'resolved', label: 'outreach_bounced' },
    auto_reply: { status: 'pending', label: 'outreach_auto_reply' },
    opt_out: { status: 'resolved', label: 'outreach_opt_out' },
    errors: { status: 'open', label: 'outreach_error' }
  }.freeze

  def initialize(user:, program_key: PROGRAM_KEY)
    @user = user
    @account = user.account
    @program_key = program_key
  end

  def call
    {
      inbox_id: campaign&.inbox_id,
      queues: queue_counts
    }
  end

  private

  attr_reader :user, :account, :program_key

  def campaign
    @campaign ||= account.outbound_campaigns.find_by(program_key: program_key)
  end

  def queue_counts
    return empty_counts unless campaign&.inbox_id

    QUEUES.transform_values do |queue|
      count_for(queue[:status], queue[:label])
    end
  end

  def empty_counts
    QUEUES.transform_values { 0 }
  end

  def count_for(status, label)
    finder = ConversationFinder.new(
      user,
      {
        inbox_id: campaign.inbox_id,
        status: status,
        labels: [label],
        assignee_type: 'all'
      }
    )

    finder.perform_meta_only.dig(:count, :all_count).to_i
  end
end
