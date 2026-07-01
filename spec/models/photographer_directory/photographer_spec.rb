# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhotographerDirectory::Photographer do
  let(:secondary_db_configured) { ENV['PHOTOGRAPHER_DIRECTORY_DATABASE_URL'].present? }

  describe 'writable columns contract' do
    it 'declares exactly the four consent columns in CONSENT_WRITABLE_COLUMNS' do
      expect(described_class::CONSENT_WRITABLE_COLUMNS).to contain_exactly(
        'marketing_consent',
        'unsubscribed_from_all_campaigns',
        'unsubscribed_from_all_at',
        'gdpr_delete_requested_at'
      )
    end
  end

  describe 'attr_readonly enforcement' do
    before { skip 'secondary DB not configured' unless secondary_db_configured }

    it 'makes every non-consent column read-only at the ORM layer' do
      described_class.lock_non_consent_columns!

      readonly = described_class.readonly_attributes.to_a
      non_writable = described_class.column_names - described_class::WRITABLE_COLUMNS

      non_writable.each do |col|
        expect(readonly).to include(col), "expected #{col} to be readonly"
      end
    end

    it 'does not mark the four consent columns read-only' do
      described_class.lock_non_consent_columns!

      readonly = described_class.readonly_attributes.to_a
      described_class::WRITABLE_COLUMNS.each do |col|
        expect(readonly).not_to include(col), "did not expect #{col} to be readonly"
      end
    end
  end

  describe '.queryable_for_outreach' do
    before { skip 'secondary DB not configured' unless secondary_db_configured }

    it 'filters on email presence, valid validation, consent, opt-out, GDPR, and active status' do
      sql = described_class.queryable_for_outreach.to_sql

      expect(sql).to match(/"email" IS NULL/i)  # inside NOT (...) per Rails `where.not` translation
      expect(sql).to include("'valid'")
      expect(sql).to include('"marketing_consent" = TRUE')
      expect(sql).to include('"unsubscribed_from_all_campaigns" = FALSE')
      expect(sql).to include('"gdpr_delete_requested_at" IS NULL')
      expect(sql).to include("'active'")
    end
  end

  describe 'connection routing' do
    before { skip 'secondary DB not configured' unless secondary_db_configured }

    it 'uses the photographer_directory connection, not primary' do
      primary_db = ActiveRecord::Base.connection_db_config.database
      pd_db = described_class.connection_db_config.database

      expect(pd_db).not_to eq(primary_db)
      expect(pd_db).to eq('photographer_directory')
    end

    it 'resolves the photographer_photographers table' do
      expect(described_class.table_name).to eq('photographer_photographers')
      expect(described_class.column_names).to include(*described_class::WRITABLE_COLUMNS)
    end
  end
end
