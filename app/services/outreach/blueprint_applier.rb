# Applies a YAML campaign blueprint to an Account.
#
# Idempotent: re-running does not duplicate rows. Template bodies are
# updated in place when (slot, locale) matches; templates absent from the
# YAML are soft-deactivated (active: false) rather than deleted, preserving
# an audit trail. Stages are upserted by (program_key, stage.key) and
# wrapped in a single transaction per campaign — partial failures roll
# back cleanly.
#
# Usage:
#   Outreach::BlueprintApplier.new(account: account, path: path).apply!
class Outreach::BlueprintApplier
  class BlueprintError < StandardError; end

  REQUIRED_KEYS = %w[program_key name stages templates].freeze
  REQUIRED_STAGE_KEYS = %w[key on_enter_action position].freeze
  REQUIRED_TEMPLATE_KEYS = %w[slot locale subject body].freeze

  def initialize(account:, path:)
    @account = account
    @path = path
  end

  def apply!
    blueprint = load_and_validate

    ActiveRecord::Base.transaction do
      campaign = upsert_campaign(blueprint)
      upsert_stages(campaign, blueprint.fetch('stages'))
      upsert_templates(campaign, blueprint.fetch('templates'))
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
    validate_templates!(raw.fetch('templates'))
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

  def validate_templates!(templates)
    raise BlueprintError, "#{path}: 'templates' must be a non-empty array" unless templates.is_a?(Array) && templates.any?

    templates.each_with_index do |template, idx|
      missing = REQUIRED_TEMPLATE_KEYS - template.keys
      next if missing.empty?

      raise BlueprintError, "#{path}: template ##{idx} missing keys: #{missing.join(', ')}"
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
    campaign.save!
    campaign
  end

  def upsert_stages(campaign, stages)
    # Two-pass save: core attrs first, cross-stage wiring second. This avoids
    # tripping the next_stage_key validation during partial application.
    stages.each { |attrs| upsert_stage_core!(campaign, attrs) }

    # Remove stages no longer in YAML before wiring cross-references, so
    # dangling next_stage_key / branch_rule targets fail validation loudly.
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

  def upsert_templates(campaign, templates)
    yaml_slot_locales = templates.map { |t| [t.fetch('slot'), t.fetch('locale')] }

    templates.each do |template_attrs|
      slot = template_attrs.fetch('slot')
      locale = template_attrs.fetch('locale')

      template = campaign.templates.where(slot: slot, locale: locale).order(active: :desc, updated_at: :desc).first ||
                 campaign.templates.build(slot: slot, locale: locale)
      template.assign_attributes(
        subject: template_attrs.fetch('subject'),
        body: template_attrs.fetch('body'),
        llm_guidance: template_attrs['llm_guidance'],
        active: true
      )
      template.save!
    end

    # Soft-deactivate any active template whose (slot, locale) is no longer in YAML.
    campaign.templates.where(active: true).find_each do |template|
      next if yaml_slot_locales.include?([template.slot, template.locale])

      template.update!(active: false)
    end
  end
end
