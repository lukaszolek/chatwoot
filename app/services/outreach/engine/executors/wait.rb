# Wait executor: keeps the participant parked in the current stage until
# `stage_entered_at + auto_advance_after_hours` has passed, then
# transitions to `next_stage_key`.
#
# The Runner picks up any participant whose `next_action_at <= now`.
# Because the preceding SendTemplate transitioned with next_action_at=now
# (so it doesn't stall under the default transition), we land in Wait
# immediately and must gate the actual move. If the wait window is still
# open, push `next_action_at` out to the due time and leave the stage
# alone. If it has elapsed, transition forward.
class Outreach::Engine::Executors::Wait < Outreach::Engine::Executors::Base
  def call
    if stage.next_stage_key.blank?
      pause_terminal!(reason: "wait_without_next_stage:#{stage.key}")
      return
    end

    hours = stage.auto_advance_after_hours.to_i
    due_at = participant.stage_entered_at + hours.hours

    if hours.positive? && due_at > Time.current
      participant.update!(next_action_at: due_at)
      return
    end

    transition_to!(stage.next_stage_key)
  end
end
