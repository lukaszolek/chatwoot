# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::RateLimiter do
  before { flush_outreach_rate_limit_keys }

  describe '#reserve!' do
    it 'returns true when under the cap and increments the counter' do
      limiter = described_class.new('gmail.com', max_per_hour: 3)

      expect(limiter.reserve!).to be(true)
      expect(limiter.reserve!).to be(true)
      expect(limiter.current_count).to eq(2)
    end

    it 'returns false and backs out the reservation when the cap is hit' do
      limiter = described_class.new('gmail.com', max_per_hour: 2)

      2.times { expect(limiter.reserve!).to be(true) }
      expect(limiter.reserve!).to be(false)

      # over-reservation rolled back so current_count equals cap, not cap+1
      expect(limiter.current_count).to eq(2)
    end

    it 'segregates by recipient domain' do
      gmail = described_class.new('gmail.com', max_per_hour: 1)
      yahoo = described_class.new('yahoo.com', max_per_hour: 1)

      expect(gmail.reserve!).to be(true)
      expect(yahoo.reserve!).to be(true)
      expect(gmail.reserve!).to be(false)
      expect(yahoo.reserve!).to be(false)
    end

    it 'starts a fresh window in the next hour bucket' do
      now = Time.zone.parse('2026-04-22 10:00:00')
      a = described_class.new('gmail.com', max_per_hour: 1, now: now)
      b = described_class.new('gmail.com', max_per_hour: 1, now: now + 1.hour)

      expect(a.reserve!).to be(true)
      expect(a.reserve!).to be(false)
      expect(b.reserve!).to be(true) # new bucket, fresh counter
    end

    it 'fails open when Redis raises' do
      limiter = described_class.new('gmail.com', max_per_hour: 1)
      allow(Redis::Alfred).to receive(:incr).and_raise('redis down')

      expect(limiter.reserve!).to be(true)
    end

    it 'returns true without touching Redis for an empty domain' do
      expect(Redis::Alfred).not_to receive(:incr)
      expect(described_class.new('', max_per_hour: 0).reserve!).to be(true)
    end
  end

  describe '.domain_from_email' do
    it 'extracts lowercase domain' do
      expect(described_class.domain_from_email('Alex@Studio-ALEX.TEST')).to eq('studio-alex.test')
    end

    it 'returns an empty string on malformed input' do
      expect(described_class.domain_from_email('no-at-sign')).to eq('')
      expect(described_class.domain_from_email(nil)).to eq('')
    end
  end

  def flush_outreach_rate_limit_keys
    Redis::Alfred.scan_each(match: "#{described_class::KEY_PREFIX}:*") { |k| Redis::Alfred.delete(k) }
  end
end
