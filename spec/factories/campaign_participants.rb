# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_participant do
    association :outbound_campaign
    association :account
    current_stage_key { 'intro' }
    stage_entered_at { Time.current }
    next_action_at { Time.current }

    after(:build) do |participant|
      participant.account ||= participant.outbound_campaign.account
      participant.participatable ||= create(:photographer_partner_profile, account: participant.account)
    end
  end
end
