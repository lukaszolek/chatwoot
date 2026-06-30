# frozen_string_literal: true

FactoryBot.define do
  factory :photographer_partner_profile do
    association :account
    sequence(:external_id) { |n| "ext-#{n}" }
    partnership_status { :imported }
  end
end
