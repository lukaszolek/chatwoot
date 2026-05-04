# Runs one claimed campaign participant through the outreach engine.
# Runner#tick only claims due rows and enqueues this job, so slow LLM calls
# can run in parallel without letting later cron ticks pick the same row.
class Outreach::ParticipantTickJob < ApplicationJob
  queue_as :outreach

  def perform(participant_id)
    participant = CampaignParticipant.find_by(id: participant_id)
    return unless participant

    campaign = participant.outbound_campaign
    return unless campaign&.active?

    Outreach::Engine::Runner.new(campaign).process(participant)
  end
end
