# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::PhotographerDirectory::ConsentWriter do
  let(:account) { create(:account) }
  let!(:campaign) do
    create(:outbound_campaign, :photographer_partnership, :active, account: account)
  end
  let(:profile) do
    create(:photographer_partner_profile, account: account, external_id: '42',
                                          partnership_status: :contacted)
  end

  # Stub the secondary-DB row so we don't hit production Postgres in specs.
  def stub_source_photographer
    source = instance_double(PhotographerDirectory::Photographer, id: 42)
    allow(source).to receive_messages(opt_out!: true, request_gdpr_delete!: true)
    allow(PhotographerDirectory::Photographer).to receive(:find_by).with(id: '42').and_return(source)
    source
  end

  describe '#propagate_opt_out' do
    it 'writes opt_out to the source, transitions the profile, and logs an attribution event' do
      source = stub_source_photographer

      described_class.new(profile).propagate_opt_out(reason: 'list_unsubscribe')

      expect(source).to have_received(:opt_out!)
      expect(profile.reload.partnership_status).to eq('do_not_contact')
      participant = CampaignParticipant.find_by(participatable: profile)
      expect(participant.attribution_events.where(event_type: :unsubscribe).count).to eq(1)
    end

    it 'is idempotent within the 24h window — second call is a no-op' do
      stub_source_photographer
      writer = described_class.new(profile)
      writer.propagate_opt_out(reason: 'list_unsubscribe')

      expect { writer.propagate_opt_out(reason: 'list_unsubscribe') }
        .not_to change(CampaignAttributionEvent, :count)
    end

    it 'records a fresh event once the idempotency window elapses' do
      stub_source_photographer
      writer = described_class.new(profile)
      writer.propagate_opt_out(reason: 'list_unsubscribe')

      travel_to(25.hours.from_now) do
        expect { writer.propagate_opt_out(reason: 'operator_manual') }
          .to change(CampaignAttributionEvent, :count).by(1)
      end
    end
  end

  describe '#propagate_gdpr_delete' do
    it 'requests GDPR delete on the source and marks the profile do_not_contact' do
      source = stub_source_photographer

      described_class.new(profile).propagate_gdpr_delete

      expect(source).to have_received(:request_gdpr_delete!)
      expect(profile.reload.partnership_status).to eq('do_not_contact')
    end
  end

  describe '#propagate_bounce' do
    it 'treats a hard bounce as opt-out + logs bounce event_type' do
      source = stub_source_photographer

      described_class.new(profile).propagate_bounce(reason: 'hard_bounce')

      expect(source).to have_received(:opt_out!)
      participant = CampaignParticipant.find_by(participatable: profile)
      expect(participant.attribution_events.where(event_type: :email_bounce).count).to eq(1)
    end
  end

  describe 'error path' do
    it 'raises PhotographerNotFound when the source row is missing' do
      allow(PhotographerDirectory::Photographer).to receive(:find_by).with(id: '42').and_return(nil)

      expect { described_class.new(profile).propagate_opt_out(reason: 'x') }
        .to raise_error(described_class::PhotographerNotFound, /external_id=42/)
    end
  end

  describe 'synthetic participant fallback' do
    it 'creates a paused terminal participant when no participant exists yet' do
      stub_source_photographer
      expect(profile.reload).to have_attributes(partnership_status: 'contacted')

      expect { described_class.new(profile).propagate_opt_out(reason: 'list_unsubscribe') }
        .to change(CampaignParticipant, :count).by(1)

      participant = CampaignParticipant.find_by(participatable: profile)
      expect(participant).to have_attributes(current_stage_key: 'terminal', paused: true)
      expect(participant.metadata['synthetic_for_consent_audit']).to be(true)
    end

    it 'reuses an existing participant instead of creating a synthetic one' do
      stub_source_photographer
      real = create(:campaign_participant, outbound_campaign: campaign, account: account,
                                           participatable: profile, current_stage_key: 'reminder_wait')

      described_class.new(profile).propagate_opt_out(reason: 'list_unsubscribe')

      expect(CampaignParticipant.where(participatable: profile).count).to eq(1)
      expect(real.reload.attribution_events.where(event_type: :unsubscribe).count).to eq(1)
    end
  end
end

RSpec.describe Outreach::PhotographerDirectory::PropagateConsentJob do
  let(:account) { create(:account) }
  let(:profile) { create(:photographer_partner_profile, account: account) }

  describe '#perform' do
    it 'dispatches opt_out to ConsentWriter' do
      writer = instance_double(Outreach::PhotographerDirectory::ConsentWriter)
      allow(Outreach::PhotographerDirectory::ConsentWriter)
        .to receive(:new).with(profile).and_return(writer)
      allow(writer).to receive(:propagate_opt_out)

      described_class.new.perform(profile.id, 'opt_out', reason: 'list_unsubscribe')

      expect(writer).to have_received(:propagate_opt_out).with(reason: 'list_unsubscribe')
    end

    it 'raises ArgumentError for an unknown action' do
      expect { described_class.new.perform(profile.id, 'bogus') }
        .to raise_error(ArgumentError, /bogus/)
    end

    it 'enqueues on the outreach queue' do
      expect { described_class.perform_later(profile.id, 'opt_out', reason: 'x') }
        .to have_enqueued_job(described_class).on_queue('outreach')
    end
  end
end
