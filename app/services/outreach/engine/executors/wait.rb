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

    return if halt_for_disabled_followup_locale?

    transition_to!(stage.next_stage_key)
  end

  private

  def halt_for_disabled_followup_locale?
    return false unless next_stage_followup_send?
    return false if enabled_followup_locales.include?(participant_locale)

    participant.update!(
      paused: true,
      next_action_at: nil,
      metadata: participant.metadata.to_h.merge('paused_reason' => "followup_disabled_for_locale:#{participant_locale}")
    )
    true
  end

  def next_stage_followup_send?
    %w[reminder breakup].include?(next_stage&.template_slot.to_s)
  end

  def next_stage
    @next_stage ||= campaign.pipeline_stages.find_by(key: stage.next_stage_key)
  end

  def enabled_followup_locales
    configured = (campaign.config || {})['followup_enabled_locales']
    enabled = configured.presence ||
              Outreach::Engine::Executors::SendTemplate::DEFAULT_FOLLOWUP_ENABLED_LOCALES[campaign.program_key]
    Array(enabled).map { |locale| locale.to_s.downcase }
  end

  def participant_locale
    @participant_locale ||= begin
      locale = (participant.metadata || {})['locale'].presence ||
               participant.participatable.try(:preferred_language).presence ||
               (campaign.config || {})['default_locale'].presence ||
               'en'
      locale.to_s.downcase
    end
  end
end
