# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_template do
    association :outbound_campaign
    sequence(:slot) { |n| "slot_#{n}" }
    locale { 'en' }
    sequence(:subject) { |n| "Subject #{n}" }
    body { 'Hello {{first_name}}' }
    active { true }
  end
end
