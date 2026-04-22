# Base class for pipeline stage executors. Each `on_enter_action` enum
# value in CampaignPipelineStage has a matching executor that mutates
# the participant and records side effects. Executors run inside a
# single-participant transaction held by the Runner.
#
# Subclasses implement `#call` and may advance `current_stage_key` /
# `next_action_at` / `paused` on the participant. They raise on
# unrecoverable errors; the Runner catches and backs off `next_action_at`
# so a bad participant does not hot-loop.
class Outreach::Engine::Executors::Base
  def initialize(participant:, stage:)
    @participant = participant
    @stage = stage
  end

  def call
    raise NotImplementedError, "#{self.class.name} must implement #call"
  end

  protected

  attr_reader :participant, :stage

  def campaign
    participant.outbound_campaign
  end

  def transition_to!(stage_key, next_action_at: Time.current)
    participant.update!(
      current_stage_key: stage_key,
      stage_entered_at: Time.current,
      next_action_at: next_action_at
    )
  end

  def pause_terminal!(reason: nil)
    metadata = participant.metadata || {}
    metadata = metadata.merge('paused_reason' => reason) if reason
    participant.update!(paused: true, metadata: metadata)
  end
end
