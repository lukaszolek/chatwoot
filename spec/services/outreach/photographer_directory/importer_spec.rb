# frozen_string_literal: true

require 'rails_helper'

SOURCE_ROW_STRUCT = Struct.new(
  :id, :email, :business_name, :owner_name, :website, :phone,
  :country_code, :instagram_handle, :preferred_language,
  :marketing_consent, :gdpr_delete_requested_at, :status,
  keyword_init: true
)

RSpec.describe Outreach::PhotographerDirectory::Importer do
  let(:account) { create(:account) }

  # A stand-in for PhotographerDirectory::Photographer — we don't want to hit
  # the secondary DB in these specs. Using a Struct instead of a double keeps
  # the shape explicit and easy to extend.
  def source_row(overrides = {})
    defaults = {
      id: 42, email: 'alex@example.com', business_name: 'Alex Studio',
      owner_name: 'Alex Example', website: 'https://example.com',
      phone: '+49123', country_code: 'DE', instagram_handle: 'alex',
      preferred_language: 'de', marketing_consent: true,
      gdpr_delete_requested_at: nil, status: 'active'
    }
    SOURCE_ROW_STRUCT.new(**defaults, **overrides)
  end

  # Stub the scope-query so the batched iteration yields the rows we provide.
  def stub_query_with(importer, rows)
    scope = instance_double(ActiveRecord::Relation)
    allow(scope).to receive(:find_in_batches).and_yield(rows)
    allow(importer).to receive(:source_query).and_return(scope)
  end

  describe '#perform' do
    it 'imports a new row — creates Contact and PhotographerPartnerProfile' do
      importer = described_class.new(account: account)
      stub_query_with(importer, [source_row])

      result = importer.perform

      expect(result.imported).to eq(1)
      expect(result.updated).to eq(0)
      profile = PhotographerPartnerProfile.find_by(account: account, external_id: '42')
      expect(profile).to have_attributes(
        email: 'alex@example.com', business_name: 'Alex Studio',
        preferred_language: 'de', partnership_status: 'imported',
        marketing_consent: true
      )
      expect(profile.contact).to be_present
      expect(profile.contact.identifier).to eq('photographer_directory:42')
    end

    it 'is a no-op for unchanged rows (counts as updated but does not duplicate records)' do
      importer = described_class.new(account: account)
      stub_query_with(importer, [source_row])

      importer.perform
      expect { importer.perform }
        .to not_change(PhotographerPartnerProfile, :count)
        .and not_change(Contact, :count)
    end

    it 'flags previously_do_not_contact when directory reports consent for a rejected profile' do
      importer = described_class.new(account: account)
      stub_query_with(importer, [source_row])
      importer.perform
      profile = PhotographerPartnerProfile.find_by(account: account, external_id: '42')
      profile.update!(partnership_status: :do_not_contact)

      importer.perform

      expect(profile.reload.metadata['previously_do_not_contact']).to be(true)
      expect(profile.partnership_status).to eq('imported')
    end

    it 'preserves non-terminal partnership_status across re-imports (does not reset signed_up)' do
      importer = described_class.new(account: account)
      stub_query_with(importer, [source_row])
      importer.perform
      profile = PhotographerPartnerProfile.find_by(account: account, external_id: '42')
      profile.update!(partnership_status: :signed_up)

      importer.perform

      expect(profile.reload.partnership_status).to eq('signed_up')
    end

    it 'isolates per-row failures so one bad row does not abort the batch' do
      good = source_row(id: 1, email: 'good@example.com')
      bad  = source_row(id: 2, email: nil) # email presence validation fails on profile save
      importer = described_class.new(account: account)
      stub_query_with(importer, [good, bad])

      result = importer.perform

      expect(result.imported).to eq(1)
      expect(result.failed).to eq(1)
      expect(PhotographerPartnerProfile.where(account: account).count).to eq(1)
    end

    it 'scopes the import per account — duplicate external_id across accounts both persist' do
      other_account = create(:account)
      row = source_row
      importer_a = described_class.new(account: account)
      importer_b = described_class.new(account: other_account)
      stub_query_with(importer_a, [row])
      stub_query_with(importer_b, [row])

      importer_a.perform
      importer_b.perform

      expect(PhotographerPartnerProfile.where(external_id: '42').pluck(:account_id))
        .to contain_exactly(account.id, other_account.id)
    end

    it 'reuses the existing Contact on re-import rather than creating a duplicate' do
      importer = described_class.new(account: account)
      stub_query_with(importer, [source_row])

      expect { 2.times { importer.perform } }.to change(Contact, :count).by(1)
    end
  end
end
