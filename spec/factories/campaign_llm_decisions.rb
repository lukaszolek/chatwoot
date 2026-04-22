# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_llm_decision do
    association :campaign_participant
    decision_type { :classify_reply }
    model { 'deepseek/deepseek-v3.2-exp' }
    confidence { 0.9 }
    output { { intent_class: 'interested_signup', reasoning: 'test' } }

    after(:build) do |decision|
      decision.outbound_campaign ||= decision.campaign_participant.outbound_campaign
    end
  end
end
