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

  describe '#build_excerpt' do
    it 'removes document-photo lines when the same page contains stronger family signals' do
      markdown = <<~TEXT
        Séances famille, grossesse et mariage en lumière naturelle.
        Photos d'identité conformes ANTS, e-photo et documents officiels.
      TEXT

      excerpt = snippet_selector.send(:build_excerpt, markdown)

      expect(excerpt).to include('Séances famille, grossesse et mariage')
      expect(excerpt).not_to include("Photos d'identité")
    end

    it 'removes framed-print sales lines when the same page contains personal session signals' do
      markdown = <<~TEXT
        Portraits et séances famille pleines de douceur et d'émotion.
        Tirages encadrés disponibles en option dans la boutique du studio.
      TEXT

      excerpt = snippet_selector.send(:build_excerpt, markdown)

      expect(excerpt).to include('Portraits et séances famille')
      expect(excerpt).not_to include('Tirages encadrés')
    end

    it 'keeps low-fit lines when no better category exists on the page' do
      markdown = <<~TEXT
        Photos d'identité conformes ANTS et documents officiels.
        Passeports, visas et photos administratives au studio.
      TEXT

      excerpt = snippet_selector.send(:build_excerpt, markdown)

      expect(excerpt).to include("Photos d'identité")
      expect(excerpt).to include('Passeports')
    end
  end
end
