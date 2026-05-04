# The engine runner iterates participants whose `next_action_at` has
# passed and dispatches each through the executor matching their current
# stage's `on_enter_action`.
#
# One tick call handles up to BATCH_SIZE participants per campaign. The
# TickSchedulerJob (every 5 min) fans out per active campaign so batches
# run independently. Each participant's transition is wrapped in a
# transaction — a failure rolls back state mutations and the runner
# logs + pushes `next_action_at` out by BACKOFF to avoid hot-looping.
class Outreach::Engine::Runner
  DEFAULT_BATCH_SIZE = 200
  BACKOFF = 10.minutes

  ACTION_TO_EXECUTOR = {
    'send_template' => Outreach::Engine::Executors::SendTemplate,
    'wait' => Outreach::Engine::Executors::Wait,
    'classify_reply' => Outreach::Engine::Executors::ClassifyReply,
    'escalate_to_user' => Outreach::Engine::Executors::EscalateToUser,
    'terminal' => Outreach::Engine::Executors::Terminal
  }.freeze

  class UnknownActionError < StandardError; end

  def initialize(campaign)
    @campaign = campaign
  end

  def tick
    return 0 unless @campaign.active?

    participants = due_participants.to_a
    Rails.logger.info(
      "[outreach.runner] campaign=#{@campaign.id} program=#{@campaign.program_key} batch=#{participants.size}"
    )

    participants.each { |p| execute(p) }
    participants.size
  end

  private

  def due_participants
    @campaign.participants
             .due_for_tick
             .includes(:participatable)
             .limit(batch_size)
  end

  def batch_size
    (@campaign.config || {})['tick_batch_size'].to_i.positive? ? @campaign.config['tick_batch_size'].to_i : DEFAULT_BATCH_SIZE
  end

  def execute(participant)
    ActiveRecord::Base.transaction do
      participant.with_lock do
        participant.reload
        next unless executable?(participant)

        stage = lookup_stage(participant)
        if stage
          executor_for(stage).new(participant: participant, stage: stage).call
        else
          handle_missing_stage(participant)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error(
      "[outreach.runner] participant=#{participant.id} stage=#{participant.current_stage_key} " \
      "error=#{e.class.name}: #{e.message}"
    )
    back_off!(participant, reason: "executor_error:#{e.class.name}")
  end

  def executable?(participant)
    return false if participant.paused?
    return false if participant.next_action_at.blank?

    participant.next_action_at <= Time.current
  end

  def handle_missing_stage(participant)
    Rails.logger.warn(
      "[outreach.runner] participant=#{participant.id} has no stage for key=#{participant.current_stage_key}"
    )
    back_off!(participant, reason: "missing_stage:#{participant.current_stage_key}")
  end

  def executor_for(stage)
    ACTION_TO_EXECUTOR[stage.on_enter_action.to_s] ||
      raise(UnknownActionError, "No executor for on_enter_action=#{stage.on_enter_action} (stage key=#{stage.key})")
  end

  def lookup_stage(participant)
    @stage_cache ||= @campaign.pipeline_stages.index_by(&:key)
    @stage_cache[participant.current_stage_key]
  end

  def back_off!(participant, reason:)
    metadata = (participant.metadata || {}).merge('last_error' => reason, 'last_error_at' => Time.current.iso8601)
    # update_columns intentionally skips validations/callbacks — this runs
    # inside the runner's rescue path after a transaction rollback, where
    # we must not re-enter validation logic that might itself raise.
    participant.update_columns( # rubocop:disable Rails/SkipsModelValidations
      next_action_at: Time.current + BACKOFF,
      metadata: metadata,
      updated_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[outreach.runner] back_off! failed for participant=#{participant.id}: #{e.message}")
  end
end
