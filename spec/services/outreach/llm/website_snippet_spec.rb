require 'rails_helper'

RSpec.describe Outreach::Llm::WebsiteSnippet do
  subject(:snippet_selector) { described_class.new(profile) }

  let(:profile) { instance_double(PhotographerPartnerProfile, website: 'https://example.test') }

  describe '#best_page_from_pairs' do
    let(:family_homepage) do
      instance_double(
        PhotographerDirectory::Page,
        content_markdown: 'Photographe de mariage, grossesse et famille en Provence.',
        title: 'Accueil'
      )
    end

    let(:corporate_portfolio) do
      instance_double(
        PhotographerDirectory::Page,
        content_markdown: 'Corporate headshots, immobilier and product photography for brands.',
        title: 'Portfolio'
      )
    end

    let(:generic_about) do
      instance_double(
        PhotographerDirectory::Page,
        content_markdown: 'Photographe professionnelle basee a Lyon pour vos projets photo.',
        title: 'About'
      )
    end

    it 'prefers family and wedding signals over low-fit categories when both exist on the domain' do
      pairs = [
        [corporate_portfolio, 'portfolio'],
        [family_homepage, 'homepage']
      ]

      expect(snippet_selector.send(:best_page_from_pairs, pairs)).to eq(family_homepage)
    end

    it 'keeps the default page-type fallback when no family or wedding signal exists anywhere' do
      pairs = [
        [corporate_portfolio, 'portfolio'],
        [generic_about, 'about']
      ]

      expect(snippet_selector.send(:best_page_from_pairs, pairs)).to eq(generic_about)
    end
  end
end
