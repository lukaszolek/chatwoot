# Discards all pending outreach drafts in a conversation without escalating the
# participant. Used when the operator decides the thread should stop waiting
# for approval (for example Not relevant / Opt-out).
class Outreach::Drafts::DiscardPendingConversationDraftsService
  def initialize(conversation:, reason:, user: nil)
    @conversation = conversation
    @user = user
    @reason = reason
  end

  def call
    discarded = 0

    conversation.messages.pending_outreach_drafts.find_each do |draft|
      Outreach::Drafts::DiscardService.new(
        draft_message: draft,
        user: user,
        reason: reason
      ).call
      discarded += 1
    end

    discarded
  end

  private

  attr_reader :conversation, :user, :reason
end
