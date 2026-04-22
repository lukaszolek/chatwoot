# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_pipeline_stage do
    association :outbound_campaign
    sequence(:key) { |n| "stage_#{n}" }
    sequence(:position) { |n| n }
    on_enter_action { :wait }
    auto_advance_after_hours { 24 }

    trait :intro do
      key { 'intro' }
      on_enter_action { :send_template }
      template_slot { 'intro' }
    end

    trait :reply_router do
      key { 'reply_router' }
      on_enter_action { :classify_reply }
      branch_rules do
        {
          interested_signup: { target: 'escalated', min_confidence: 0.85 },
          declined: { target: 'terminal', min_confidence: 0.85 }
        }
      end
    end

    trait :terminal do
      key { 'terminal' }
      on_enter_action { :terminal }
    end
  end
end
