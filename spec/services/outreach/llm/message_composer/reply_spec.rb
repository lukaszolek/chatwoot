require 'rails_helper'

RSpec.describe Outreach::Llm::MessageComposer::Reply do
  let(:participatable) { instance_double(PhotographerPartnerProfile, email: 'pauline@example.com') }
  let(:participant) do
    instance_double(CampaignParticipant, conversation: nil, outbound_campaign: nil, participatable: participatable)
  end
  let(:toolbox) { instance_double(Outreach::Agent::Toolbox, tools: []) }
  let(:client) { instance_double(Outreach::Llm::Client, compose_model: 'deepseek/deepseek-v4-flash') }
  let(:composer) { described_class.new(participant: participant, toolbox: toolbox, locale: 'fr') }

  before do
    allow(composer).to receive(:client).and_return(client)
    allow(composer).to receive(:build_user_prompt).and_return('user prompt')
    allow(composer).to receive(:build_system_prompt).and_return('system prompt')
    allow(composer).to receive(:infer_subject_from_thread).and_return('Re: test')
  end

  it 'retries once when the reply body contains unresolved placeholders' do
    allow(client).to receive(:ask_with_tools!).and_return(
      {
        parsed: { 'body' => 'Bonjour {{first_name}}, merci.' },
        raw_content: 'Bonjour {{first_name}}, merci.',
        tool_calls: [],
        token_usage: {},
        provider_metadata: {},
        latency_ms: 10
      },
      {
        parsed: { 'body' => 'Bonjour Pauline, merci.' },
        raw_content: 'Bonjour Pauline, merci.',
        tool_calls: [],
        token_usage: {},
        provider_metadata: {},
        latency_ms: 12
      }
    )

    result = composer.call

    expect(client).to have_received(:ask_with_tools!).twice
    expect(result[:escalate]).not_to be(true)
    expect(result[:body]).to eq('Bonjour Pauline, merci.')
  end

  it 'escalates when placeholders remain after retry' do
    allow(client).to receive(:ask_with_tools!).and_return(
      {
        parsed: { 'body' => 'Bonjour {{first_name}}, merci.' },
        raw_content: 'Bonjour {{first_name}}, merci.',
        tool_calls: [],
        token_usage: {},
        provider_metadata: {},
        latency_ms: 10
      }
    )

    result = composer.call

    expect(client).to have_received(:ask_with_tools!).twice
    expect(result[:escalate]).to be(true)
    expect(result[:reason]).to include('invalid_output:')
  end

  it 'explicitly forbids the legal footer in normal in-thread replies' do
    instruction = composer.send(:slot_instruction)

    expect(instruction).to include('Do NOT append the outreach legal footer')
    expect(instruction).to include('privacy-policy')
    expect(instruction).to include('generic STOP opt-out')
    expect(instruction).to include('Answer the latest inbound question directly')
    expect(instruction).to include('conversation history already contains the registration')
  end
end
