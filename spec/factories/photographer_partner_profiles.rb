# frozen_string_literal: true

FactoryBot.define do
  factory :photographer_partner_profile do
    association :account
    sequence(:external_id) { |n| "ext-#{n}" }
    sequence(:email) { |n| "photographer#{n}@example.com" }
    sequence(:business_name) { |n| "Studio #{n}" }
    owner_name { 'Alex Example' }
    website { 'https://example.com' }
    country_code { 'DE' }
    preferred_language { 'de' }
    marketing_consent { true }
    partnership_status { :imported }
  end
end
