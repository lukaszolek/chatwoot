# Applies a YAML campaign blueprint to an Account.
#
# Idempotent: re-running does not duplicate rows. Stages are upserted by
# (program_key, stage.key) and wrapped in a single transaction per campaign
# — partial failures roll back cleanly. Knowledge documents are seeded
# only on first apply (when the campaign has no documents yet); subsequent
# runs leave them alone so operator edits in the UI aren't clobbered.
#
# Usage:
#   Outreach::BlueprintApplier.new(account: account, path: path).apply!
class Outreach::BlueprintApplier
  class BlueprintError < StandardError; end

  REQUIRED_KEYS = %w[program_key name stages].freeze
  REQUIRED_STAGE_KEYS = %w[key on_enter_action position].freeze

  def initialize(account:, path:)
    @account = account
    @path = path
  end

  def apply!
    blueprint = load_and_validate

    ActiveRecord::Base.transaction do
      campaign = upsert_campaign(blueprint)
      upsert_stages(campaign, blueprint.fetch('stages'))
      seed_knowledge_documents(campaign) if campaign.knowledge_documents.empty?
      campaign
    end
  end

  class << self
    def apply_all(account:, blueprints_dir: default_blueprints_dir)
      Pathname.new(blueprints_dir).glob('*.yml').map do |path|
        new(account: account, path: path.to_s).apply!
      end
    end

    def default_blueprints_dir
      Rails.root.join('db/campaign_blueprints')
    end
  end

  private

  attr_reader :account, :path

  def load_and_validate
    raw = YAML.safe_load_file(path, permitted_classes: [Symbol])
    raise BlueprintError, "Blueprint at #{path} did not parse to a Hash" unless raw.is_a?(Hash)

    missing = REQUIRED_KEYS - raw.keys
    raise BlueprintError, "Blueprint at #{path} missing required keys: #{missing.join(', ')}" if missing.any?

    validate_stages!(raw.fetch('stages'))
    raw
  end

  def validate_stages!(stages)
    raise BlueprintError, "#{path}: 'stages' must be a non-empty array" unless stages.is_a?(Array) && stages.any?

    stages.each_with_index do |stage, idx|
      missing = REQUIRED_STAGE_KEYS - stage.keys
      next if missing.empty?

      raise BlueprintError, "#{path}: stage ##{idx} missing keys: #{missing.join(', ')}"
    end
  end

  def upsert_campaign(blueprint)
    campaign = OutboundCampaign.find_or_initialize_by(
      account: account,
      program_key: blueprint.fetch('program_key')
    )
    campaign.name = blueprint.fetch('name')
    campaign.config ||= {}
    default_locale = blueprint['default_locale']
    campaign.config = campaign.config.merge('default_locale' => default_locale) if default_locale
    followup_enabled_locales = blueprint['followup_enabled_locales']
    campaign.config = campaign.config.merge('followup_enabled_locales' => Array(followup_enabled_locales)) if followup_enabled_locales
    campaign.save!
    campaign
  end

  def upsert_stages(campaign, stages)
    # Two-pass save: core attrs first, cross-stage wiring second. Avoids
    # tripping next_stage_key validation during partial application.
    stages.each { |attrs| upsert_stage_core!(campaign, attrs) }

    yaml_keys = stages.map { |s| s.fetch('key') }
    campaign.pipeline_stages.reload.where.not(key: yaml_keys).destroy_all

    stages.each { |attrs| wire_stage_references!(campaign, attrs) }
  end

  def upsert_stage_core!(campaign, attrs)
    stage = campaign.pipeline_stages.find_or_initialize_by(key: attrs.fetch('key'))
    stage.assign_attributes(
      on_enter_action: attrs.fetch('on_enter_action'),
      position: attrs.fetch('position'),
      template_slot: attrs['template_slot'],
      auto_advance_after_hours: attrs['auto_advance_after_hours'],
      next_stage_key: nil,
      branch_rules: {}
    )
    stage.save!
  end

  def wire_stage_references!(campaign, attrs)
    stage = campaign.pipeline_stages.find_by!(key: attrs.fetch('key'))
    stage.update!(
      next_stage_key: attrs['next_stage_key'],
      branch_rules: attrs['branch_rules'] || {}
    )
  end

  def seed_knowledge_documents(campaign)
    Outreach::KnowledgeSeeds::PhotographerPartnership.seed!(campaign)
  end
end
