# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::Drafts::EditService do
  describe '#call' do
    it 'does not append STOP opt-out when editing a reply draft' do
      account = create(:account)
      user = create(:user, account: account)
      campaign = create(:outbound_campaign, :photographer_partnership, account: account)
      contact = create(:contact, account: account)
      participant = create(:campaign_participant, account: account, outbound_campaign: campaign, participatable: contact)
      conversation = create(:conversation, account: account, contact: contact)
      participant.update!(conversation: conversation)
      draft = create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Bonjour Elsa',
        content_attributes: { email: { subject: 'Re: framky' } },
        additional_attributes: {
          'outreach_draft' => true,
          'draft_status' => 'pending',
          'template_slot' => 'reply',
          'locale' => 'fr',
          'outbound_campaign_id' => campaign.id,
          'campaign_participant_id' => participant.id
        }
      )

      described_class.new(
        draft_message: draft,
        user: user,
        subject: 'Re: framky',
        body: 'Bonjour Elsa,' \
              "\n\nVoici le lien d'inscription au programme partenaire."
      ).call

      expect(draft.reload.content).not_to include('STOP')
      expect(draft.content).not_to include('If you do not want to receive further messages')
    end

    it 'still appends STOP opt-out when editing an intro draft' do
      account = create(:account)
      user = create(:user, account: account)
      campaign = create(:outbound_campaign, :photographer_partnership, account: account)
      contact = create(:contact, account: account)
      participant = create(:campaign_participant, account: account, outbound_campaign: campaign, participatable: contact)
      conversation = create(:conversation, account: account, contact: contact)
      participant.update!(conversation: conversation)
      draft = create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        private: true,
        content: 'Bonjour Elsa',
        content_attributes: { email: { subject: 'galeries murales' } },
        additional_attributes: {
          'outreach_draft' => true,
          'draft_status' => 'pending',
          'template_slot' => 'intro',
          'locale' => 'fr',
          'outbound_campaign_id' => campaign.id,
          'campaign_participant_id' => participant.id
        }
      )

      described_class.new(
        draft_message: draft,
        user: user,
        subject: 'galeries murales',
        body: 'Bonjour Elsa,' \
              "\n\nVoici le lien d'inscription au programme partenaire."
      ).call

      expect(draft.reload.content).to include('répondez « STOP »')
    end
  end
end
