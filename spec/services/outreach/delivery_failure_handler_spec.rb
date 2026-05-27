# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::DeliveryFailureHandler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:campaign) { create(:outbound_campaign, :active, :photographer_partnership, account: account, inbox: inbox) }
  let(:profile) { create(:photographer_partner_profile, account: account) }
  let(:contact) { create(:contact, account: account, email: 'alex@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, label_list: ['outreach_sent']) }
  let(:participant) do
    create(:campaign_participant, outbound_campaign: campaign, account: account,
                                  participatable: profile, contact: contact, conversation: conversation,
                                  current_stage_key: 'reminder_wait', last_outbound_at: 1.hour.ago)
  end

  before do
    create(:campaign_pipeline_stage, outbound_campaign: campaign, key: 'intro', position: 1,
                                     on_enter_action: :send_template, template_slot: 'intro')
    create(:campaign_pipeline_stage, outbound_campaign: campaign, key: 'reminder_send', position: 3,
                                     on_enter_action: :send_template, template_slot: 'reminder')
  end

  def outreach_message(slot:, status: :failed, created_at: Time.current)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      private: false,
      status: status,
      created_at: created_at,
      additional_attributes: {
        'outreach' => {
          'campaign_participant_id' => participant.id,
          'outbound_campaign_id' => campaign.id,
          'template_slot' => slot,
          'locale' => 'pl',
          'subject' => 'Subject'
        }
      }
    )
  end

  it 'reopens a failed intro as an outreach error and removes sent label when no mail was delivered' do
    message = outreach_message(slot: 'intro')

    described_class.new(message: message, external_error: '454 too many login attempts').call

    expect(conversation.reload.label_list).to include('outreach_error')
    expect(conversation.label_list).not_to include('outreach_sent')
    expect(participant.reload.current_stage_key).to eq('intro')
    expect(participant.next_action_at).to be_nil
    expect(participant.last_outbound_at).to be_nil
    expect(participant.metadata['last_delivery_failed_message_id']).to eq(message.id)
  end

  it 'keeps sent label and restores reminder stage when a reminder fails after a sent intro' do
    sent_intro_at = 2.hours.ago
    outreach_message(slot: 'intro', status: :sent, created_at: sent_intro_at)
    message = outreach_message(slot: 'reminder')

    described_class.new(message: message, external_error: '454 too many login attempts').call

    expect(conversation.reload.label_list).to include('outreach_sent', 'outreach_error')
    expect(participant.reload.current_stage_key).to eq('reminder_send')
    expect(participant.next_action_at).to be_nil
    expect(participant.last_outbound_at.to_i).to eq(sent_intro_at.to_i)
  end
end
