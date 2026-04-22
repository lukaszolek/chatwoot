# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_attribution_event do
    association :campaign_participant
    event_type { :partnership_signup }
    occurred_at { Time.current }
    payload { { source: 'test' } }
  end
end
