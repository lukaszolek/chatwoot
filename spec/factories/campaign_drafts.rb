# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_draft do
    association :campaign_participant
    subject { 'Draft subject' }
    body { 'Draft body' }
    template_slot { 'reply_interested_commission' }
    locale { 'en' }
    status { :pending_review }

    after(:build) do |draft|
      draft.conversation ||= create(:conversation, account: draft.campaign_participant.account)
    end
  end
end
