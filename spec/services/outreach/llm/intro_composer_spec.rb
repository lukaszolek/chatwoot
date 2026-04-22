# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Llm::IntroComposer do
  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:profile) do
    create(:photographer_partner_profile,
           account: account, preferred_language: 'pl', owner_name: 'Alex Example')
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign, account: account, participatable: profile)
  end

  def stub_client_json(parsed)
    allow_any_instance_of(Outreach::Llm::Client).to receive(:ask_json!).and_return( # rubocop:disable RSpec/AnyInstance
      parsed: parsed,
      raw_content: parsed.to_json,
      token_usage: { 'prompt_tokens' => 120, 'completion_tokens' => 40 },
      latency_ms: 220
    )
  end

  describe '#call' do
    it 'returns the opener + audit metadata when LLM succeeds' do
      allow(Outreach::Llm::WebsiteSnippet).to receive(:for).and_return(
        title: 'Portfolio — Alex', excerpt: 'Sesje plenerowe, kolor, ziarno.',
        page_type: 'portfolio', source_url: 'https://alex.test'
      )
      stub_client_json('opener' => 'Podoba mi się, że w Twoich sesjach plenerowych trzymasz ziarno.', 'reasoning' => 'cited portfolio page')

      outcome = described_class.new(participant: participant).call

      expect(outcome[:opener]).to include('ziarno')
      expect(outcome[:fallback]).to be(false)
      expect(outcome[:prompt_version]).to eq(described_class::PROMPT_VERSION)
      expect(outcome[:input_digest]).to match(/\A[a-f0-9]{64}\z/)
      expect(outcome[:token_usage]['prompt_tokens']).to eq(120)
    end

    it 'falls back to a locale-appropriate opener on LLM error' do
      allow(Outreach::Llm::WebsiteSnippet).to receive(:for).and_return(nil)
      allow_any_instance_of(Outreach::Llm::Client).to receive(:ask_json!) # rubocop:disable RSpec/AnyInstance
        .and_raise(Outreach::Llm::Client::ApiKeyMissing, 'no key')

      outcome = described_class.new(participant: participant).call

      expect(outcome[:fallback]).to be(true)
      expect(outcome[:opener]).to eq(described_class::LOCALE_FALLBACKS['pl'])
      expect(outcome[:reasoning]).to start_with('llm_error:')
    end

    it 'uses the default locale fallback when locale is unknown' do
      expect(described_class.fallback_opener('xx'))
        .to eq(described_class::LOCALE_FALLBACKS[described_class::DEFAULT_FALLBACK_LOCALE])
    end
  end
end
