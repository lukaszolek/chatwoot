# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::UnsubscribeToken do
  let(:secret) { "test-unsubscribe-secret-#{SecureRandom.hex(8)}" }

  describe 'roundtrip' do
    it 'signs and verifies with matching secret' do
      with_modified_env(described_class::SECRET_ENV => secret) do
        token = described_class.sign(participant_id: 42, campaign_id: 7)
        payload = described_class.verify(token)
        expect(payload[:participant_id]).to eq(42)
        expect(payload[:campaign_id]).to eq(7)
        expect(payload[:issued_at]).to be_a(Time)
      end
    end

    it 'rejects a token signed under a different secret' do
      stranger = described_class.new(secret: 'different-secret').sign(
        participant_id: 1, campaign_id: 1, issued_at: Time.current
      )
      with_modified_env(described_class::SECRET_ENV => secret) do
        expect { described_class.verify(stranger) }
          .to raise_error(described_class::InvalidToken, /signature mismatch/)
      end
    end

    it 'rejects a tampered signature' do
      with_modified_env(described_class::SECRET_ENV => secret) do
        token = described_class.sign(participant_id: 1, campaign_id: 1)
        tampered = Base64.urlsafe_encode64(
          Base64.urlsafe_decode64(token).sub(/.$/, 'x'),
          padding: false
        )
        expect { described_class.verify(tampered) }
          .to raise_error(described_class::InvalidToken)
      end
    end

    it 'rejects a malformed base64 payload' do
      with_modified_env(described_class::SECRET_ENV => secret) do
        expect { described_class.verify('!!!not-base64!!!') }
          .to raise_error(described_class::InvalidToken)
      end
    end

    it 'rejects expired tokens' do
      with_modified_env(described_class::SECRET_ENV => secret) do
        token = described_class.sign(participant_id: 1, campaign_id: 1, issued_at: 200.days.ago)
        expect { described_class.verify(token) }
          .to raise_error(described_class::InvalidToken, /expired/)
      end
    end
  end

  describe 'secret env' do
    it 'raises SecretMissing when OUTREACH_UNSUBSCRIBE_SECRET is blank' do
      with_modified_env(described_class::SECRET_ENV => nil) do
        expect { described_class.sign(participant_id: 1, campaign_id: 1) }
          .to raise_error(described_class::SecretMissing)
      end
    end
  end
end
