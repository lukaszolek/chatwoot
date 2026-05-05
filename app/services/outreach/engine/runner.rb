# The engine runner iterates participants whose `next_action_at` has
# passed and dispatches each through the executor matching their current
# stage's `on_enter_action`.
#
# One tick call claims up to BATCH_SIZE due participants per campaign and
# fans them out to one ParticipantTickJob each. Claiming clears
# `next_action_at` under a row lock before the slow LLM work starts, so
# overlapping cron ticks cannot enqueue the same participant repeatedly.
class Outreach::Engine::Runner
  DEFAULT_BATCH_SIZE = 200
  BACKOFF = 10.minutes
  DEFAULT_STALE_PROCESSING_AFTER = 30.minutes

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

    reclaim_stale_processing!

    participants = due_participants.to_a
    Rails.logger.info(
      "[outreach.runner] campaign=#{@campaign.id} program=#{@campaign.program_key} batch=#{participants.size}"
    )

    participants.count { |p| claim_and_enqueue(p) }
  end

  def process(participant)
    ActiveRecord::Base.transaction do
      participant.with_lock do
        participant.reload
        next if participant.paused?

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
    back_off!(participant, reason: error_reason(e))
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

  def claim_and_enqueue(participant)
    claimed = false

    participant.with_lock do
      participant.reload
      if executable?(participant)
        mark_processing!(participant)
        Outreach::ParticipantTickJob.perform_later(participant.id)
        claimed = true
      end
    end

    claimed
  end

  def executable?(participant)
    return false if participant.paused?
    return false if participant.next_action_at.blank?

    participant.next_action_at <= Time.current
  end

  def mark_processing!(participant)
    metadata = (participant.metadata || {}).merge(
      'processing_started_at' => Time.current.iso8601,
      'processing_reason' => 'outreach_runner_claim'
    )
    participant.update!(next_action_at: nil, metadata: metadata)
  end

  def reclaim_stale_processing!
    reclaimed = stale_processing_participants.count { |participant| reclaim_stale_participant(participant) }
    return if reclaimed.zero?

    Rails.logger.warn(
      "[outreach.runner] campaign=#{@campaign.id} reclaimed_stale_processing=#{reclaimed}"
    )
  end

  def stale_processing_participants
    @campaign.participants
             .where(paused: false, next_action_at: nil, conversation_id: nil)
             .where("metadata ? 'processing_started_at'")
             .where("(metadata->>'processing_started_at')::timestamptz < ?", stale_processing_cutoff)
             .limit(batch_size)
  end

  def reclaim_stale_participant(participant)
    reclaimed = false

    participant.with_lock do
      participant.reload
      if stale_processing?(participant)
        metadata = (participant.metadata || {}).merge(
          'processing_reclaimed_at' => Time.current.iso8601,
          'processing_reclaim_reason' => 'stale_outreach_runner_claim'
        )
        participant.update!(next_action_at: Time.current, metadata: metadata)
        reclaimed = true
      end
    end

    reclaimed
  end

  def stale_processing?(participant)
    return false if participant.paused?
    return false if participant.next_action_at.present?
    return false if participant.conversation_id.present?

    started_at = participant.metadata&.fetch('processing_started_at', nil)
    return false if started_at.blank?

    Time.zone.parse(started_at) < stale_processing_cutoff
  rescue ArgumentError, TypeError
    true
  end

  def stale_processing_cutoff
    Time.current - stale_processing_after
  end

  def stale_processing_after
    seconds = ENV.fetch('OUTREACH_PROCESSING_STALE_AFTER_SECONDS', DEFAULT_STALE_PROCESSING_AFTER.to_i).to_i
    seconds.positive? ? seconds.seconds : DEFAULT_STALE_PROCESSING_AFTER
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

  def error_reason(error)
    message = error.message.to_s.squish.truncate(240)
    "executor_error:#{error.class.name}:#{message}"
  end

  def back_off!(participant, reason:)
    metadata = (participant.metadata || {}).merge('last_error' => reason, 'last_error_at' => Time.current.iso8601)
    Outreach::ConversationLabels.mark_error!(participant.conversation) if participant.conversation_id
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
