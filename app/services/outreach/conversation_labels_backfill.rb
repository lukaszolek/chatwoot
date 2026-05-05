class Outreach::ConversationLabelsBackfill
  def initialize(campaign)
    @campaign = campaign
  end

  def call
    counts = { processed: 0, sent: 0, replied: 0, draft: 0, error: 0 }

    campaign.participants.includes(:conversation).find_each do |participant|
      conversation = participant.conversation
      next unless conversation

      counts[:processed] += 1
      counts[:sent] += 1 if mark_sent?(participant, conversation)
      counts[:replied] += 1 if mark_replied?(participant, conversation)
      counts[:draft] += 1 if mark_draft?(participant)
      counts[:error] += 1 if mark_error?(participant, conversation)
    end

    counts
  end

  private

  attr_reader :campaign

  def mark_sent?(participant, conversation)
    return false if participant.last_outbound_at.blank?

    Outreach::ConversationLabels.mark_sent!(conversation)
    true
  end

  def mark_replied?(participant, conversation)
    return false if participant.last_inbound_at.blank?

    Outreach::ConversationLabels.mark_replied!(conversation)
    true
  end

  def mark_draft?(participant)
    draft = pending_draft_for(participant)
    return false unless draft

    Outreach::ConversationLabels.mark_draft!(draft.conversation)
    true
  end

  def mark_error?(participant, conversation)
    metadata = participant.metadata.to_h
    return false if metadata['last_error'].blank?
    return false unless metadata['terminal_error'].present? || participant.paused?

    Outreach::ConversationLabels.mark_error!(conversation)
    true
  end

  def pending_draft_for(participant)
    Message.pending_outreach_drafts.find_by(
      "messages.additional_attributes->>'campaign_participant_id' = ?",
      participant.id.to_s
    )
  end
end
