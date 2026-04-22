# Wait executor: advances `next_action_at` by the stage's
# `auto_advance_after_hours` relative to when the participant entered
# this stage, then transitions to `next_stage_key` when due.
#
# The Runner only picks up participants whose `next_action_at` has
# already passed, so by the time Wait runs the wait window is over —
# its job is to move them forward to the next stage.
class Outreach::Engine::Executors::Wait < Outreach::Engine::Executors::Base
  def call
    if stage.next_stage_key.blank?
      pause_terminal!(reason: "wait_without_next_stage:#{stage.key}")
      return
    end

    transition_to!(stage.next_stage_key)
  end
end
