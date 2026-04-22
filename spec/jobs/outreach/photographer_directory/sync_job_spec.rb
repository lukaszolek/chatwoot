# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::PhotographerDirectory::SyncJob do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'delegates to the importer for the given account' do
      importer = instance_double(Outreach::PhotographerDirectory::Importer)
      result = Outreach::PhotographerDirectory::Importer::Result.new(
        imported: 3, updated: 1, skipped: 0, failed: 0
      )
      allow(Outreach::PhotographerDirectory::Importer)
        .to receive(:new).with(account: account, country: 'pl').and_return(importer)
      allow(importer).to receive(:perform).and_return(result)

      returned = described_class.new.perform(account.id, country: 'pl')

      expect(returned).to eq(result)
      expect(importer).to have_received(:perform)
    end

    it 'enqueues on the outreach queue' do
      expect { described_class.perform_later(account.id) }
        .to have_enqueued_job(described_class).on_queue('outreach')
    end
  end

  describe Outreach::PhotographerDirectory::ScheduledSyncJob do
    it 'enqueues a SyncJob for every account with an active photographer_partnership campaign' do
      active_account = create(:account)
      create(:outbound_campaign, :active, account: active_account, program_key: described_class::PROGRAM_KEY)

      dormant_account = create(:account)
      create(:outbound_campaign, account: dormant_account, program_key: described_class::PROGRAM_KEY, status: :draft)

      other_program_account = create(:account)
      create(:outbound_campaign, :active, account: other_program_account, program_key: 'other_program')

      described_class.new.perform

      enqueued_args = ActiveJob::Base.queue_adapter.enqueued_jobs
                                     .select { |j| j[:job] == Outreach::PhotographerDirectory::SyncJob }
                                     .map { |j| j[:args].first }
      expect(enqueued_args).to contain_exactly(active_account.id)
    end
  end
end
