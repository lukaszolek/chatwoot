# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Engine::TemplateRenderer do
  subject(:renderer) { described_class.new(template: template, participant: participant) }

  let(:account) { create(:account) }
  let(:campaign) { create(:outbound_campaign, account: account) }
  let(:profile) do
    create(:photographer_partner_profile,
           account: account,
           owner_name: 'Alex Example',
           business_name: 'Studio Alex',
           email: 'alex@studio-alex.test',
           preferred_language: 'de')
  end
  let(:participant) do
    create(:campaign_participant,
           outbound_campaign: campaign,
           account: account,
           participatable: profile,
           metadata: { 'signup_link' => 'https://framky.com/partnerships/signup?ref=alex' })
  end

  describe '#render' do
    context 'with profile + metadata placeholders' do
      let(:template) do
        build(:campaign_template,
              outbound_campaign: campaign,
              subject: 'Hey {{first_name}} — Framky partner',
              body: "Hi {{first_name}}, check out {{signup_link}}\n{{business_name}}")
      end

      it 'substitutes first_name from owner_name and metadata overrides' do
        rendered = renderer.render
        expect(rendered[:subject]).to eq('Hey Alex — Framky partner')
        expect(rendered[:body]).to eq(
          "Hi Alex, check out https://framky.com/partnerships/signup?ref=alex\nStudio Alex"
        )
      end
    end

    context 'when a placeholder is missing' do
      let(:template) do
        build(:campaign_template,
              outbound_campaign: campaign,
              subject: 'Hello {{unknown}}',
              body: 'Body')
      end

      it 'renders empty string (strict_variables disabled)' do
        expect(renderer.render[:subject]).to eq('Hello ')
      end
    end

    context 'when the template body has invalid liquid syntax' do
      let(:template) do
        build(:campaign_template,
              outbound_campaign: campaign,
              subject: 'ok',
              body: '{% if %}')
      end

      it 'raises RenderError with template id context' do
        expect { renderer.render }.to raise_error(
          Outreach::Engine::TemplateRenderer::RenderError,
          /Failed to render template/
        )
      end
    end
  end
end
