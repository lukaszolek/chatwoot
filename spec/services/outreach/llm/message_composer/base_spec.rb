require 'rails_helper'

class TestOutreachComposer < Outreach::Llm::MessageComposer::Base
  SLOT = 'intro'.freeze

  def build_user_prompt
    'user prompt'
  end

  def build_system_prompt
    'system prompt'
  end

  def slot_instruction
    'slot instruction'
  end
end

RSpec.describe Outreach::Llm::MessageComposer::Base do
  let(:participant) { instance_double(CampaignParticipant, conversation: nil, outbound_campaign: nil) }
  let(:client) { instance_double(Outreach::Llm::Client, compose_model: 'deepseek/deepseek-v4-flash') }
  let(:composer) { TestOutreachComposer.new(participant: participant, locale: 'fr') }

  before { allow(composer).to receive(:client).and_return(client) }

  it 'retries once when the model returns unresolved placeholders' do
    allow(client).to receive(:ask_json!).and_return(
      {
        parsed: { 'subject' => 'galeries murales', 'body' => 'Bonjour {{first_name}},' },
        token_usage: {},
        provider_metadata: {},
        latency_ms: 10
      },
      {
        parsed: { 'subject' => 'galeries murales', 'body' => 'Bonjour Pauline,' },
        token_usage: {},
        provider_metadata: {},
        latency_ms: 12
      }
    )

    result = composer.call

    expect(client).to have_received(:ask_json!).twice
    expect(result[:fallback]).to be(false)
    expect(result[:body]).to eq('Bonjour Pauline,')
  end

  it 'falls back when placeholders remain after retry' do
    allow(client).to receive(:ask_json!).and_return(
      {
        parsed: { 'subject' => 'galeries murales', 'body' => 'Bonjour {{first_name}},' },
        token_usage: {},
        provider_metadata: {},
        latency_ms: 10
      }
    )

    result = composer.call

    expect(client).to have_received(:ask_json!).twice
    expect(result[:fallback]).to be(true)
    expect(result[:output]['fallback']).to eq('invalid_output:unresolved_placeholders')
  end

  it 'retries once when the model returns invalid json' do
    attempts = 0
    allow(client).to receive(:ask_json!) do
      attempts += 1
      raise Outreach::Llm::Client::InvalidJson, 'invalid json' if attempts == 1

      {
        parsed: { 'subject' => 'galeries murales', 'body' => 'Bonjour Pauline,' },
        token_usage: {},
        provider_metadata: {},
        latency_ms: 12
      }
    end

    result = composer.call

    expect(client).to have_received(:ask_json!).twice
    expect(result[:fallback]).to be(false)
    expect(result[:body]).to eq('Bonjour Pauline,')
  end
end
