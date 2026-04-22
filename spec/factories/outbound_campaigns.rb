# frozen_string_literal: true

FactoryBot.define do
  factory :outbound_campaign do
    association :account
    sequence(:name) { |n| "Outbound Campaign #{n}" }
    sequence(:program_key) { |n| "program_#{n}" }
    status { :draft }
    config { { default_locale: 'en', rate_limits: { per_sender_domain: 50 } } }
    audience_source_config { { source: 'photographer_directory', filters: {} } }

    trait :active do
      status { :active }
    end

    trait :photographer_partnership do
      program_key { 'photographer_partnership' }
      name { 'Photographer Partnership' }
    end
  end
end
