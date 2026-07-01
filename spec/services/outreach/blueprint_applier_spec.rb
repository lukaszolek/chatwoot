# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::BlueprintApplier do
  let(:account) { create(:account) }
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp_dir) if tmp_dir && File.exist?(tmp_dir) }

  def write_blueprint(name, payload)
    path = File.join(tmp_dir, "#{name}.yml")
    File.write(path, payload.to_yaml)
    path
  end

  def valid_blueprint(overrides = {})
    {
      'program_key' => 'photographer_partnership',
      'name' => 'Photographer Partnership',
      'default_locale' => 'en',
      'stages' => [
        { 'key' => 'intro', 'on_enter_action' => 'send_template', 'position' => 1,
          'template_slot' => 'intro', 'next_stage_key' => 'terminal' },
        { 'key' => 'terminal', 'on_enter_action' => 'terminal', 'position' => 2 }
      ]
    }.merge(overrides)
  end

  describe '#apply!' do
    it 'creates a campaign and stages on first apply' do
      path = write_blueprint('photographer_partnership', valid_blueprint)

      campaign = described_class.new(account: account, path: path).apply!

      expect(campaign.program_key).to eq('photographer_partnership')
      expect(campaign.pipeline_stages.count).to eq(2)
      expect(campaign.config['default_locale']).to eq('en')
    end

    it 'is idempotent — second apply touches no stage count' do
      path = write_blueprint('photographer_partnership', valid_blueprint)
      described_class.new(account: account, path: path).apply!

      expect { described_class.new(account: account, path: path).apply! }
        .to not_change(OutboundCampaign, :count)
        .and not_change(CampaignPipelineStage, :count)
    end

    it 'destroys stages removed from YAML' do
      bp = valid_blueprint
      bp['stages'] << { 'key' => 'extra', 'on_enter_action' => 'terminal', 'position' => 3 }
      path = write_blueprint('photographer_partnership', bp)
      described_class.new(account: account, path: path).apply!

      bp['stages'].pop
      File.write(path, bp.to_yaml)
      described_class.new(account: account, path: path).apply!

      campaign = OutboundCampaign.find_by(program_key: 'photographer_partnership')
      expect(campaign.pipeline_stages.pluck(:key)).to contain_exactly('intro', 'terminal')
    end

    it 'raises a loud error naming the file when a required top-level key is missing' do
      bp = valid_blueprint.except('name')
      path = write_blueprint('broken', bp)

      expect { described_class.new(account: account, path: path).apply! }
        .to raise_error(described_class::BlueprintError, /broken\.yml.*name/)
    end

    it 'raises when a stage is missing required keys' do
      bp = valid_blueprint
      bp['stages'][0].delete('on_enter_action')
      path = write_blueprint('photographer_partnership', bp)

      expect { described_class.new(account: account, path: path).apply! }
        .to raise_error(described_class::BlueprintError, /on_enter_action/)
    end

    it 'rolls back the entire transaction on a mid-apply failure' do
      bp = valid_blueprint
      bp['stages'] << { 'key' => 'broken', 'on_enter_action' => 'terminal', 'position' => 3,
                        'next_stage_key' => 'ghost_stage' }
      path = write_blueprint('photographer_partnership', bp)

      expect { described_class.new(account: account, path: path).apply! }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(OutboundCampaign.where(account: account, program_key: 'photographer_partnership')).to be_empty
      expect(CampaignPipelineStage.count).to eq(0)
    end
  end

  describe '.apply_all' do
    it 'applies every YAML in the directory' do
      write_blueprint('photographer_partnership', valid_blueprint)
      write_blueprint(
        'other_program',
        valid_blueprint(
          'program_key' => 'other_program',
          'name' => 'Other',
          'stages' => [{ 'key' => 'terminal', 'on_enter_action' => 'terminal', 'position' => 1 }]
        )
      )

      described_class.apply_all(account: account, blueprints_dir: tmp_dir)

      expect(OutboundCampaign.where(account: account).pluck(:program_key))
        .to contain_exactly('photographer_partnership', 'other_program')
    end
  end
end
