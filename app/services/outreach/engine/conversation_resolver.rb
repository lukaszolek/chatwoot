# Resolves the Contact and Conversation a participant should send/receive
# messages through. Lazy — only creates rows when the engine first needs
# to send or record a message. Subsequent calls reuse the persisted ids
# on the participant.
#
# Contact is scoped per account; matched by email on the participant's
# profile. Conversation is created on the campaign's configured inbox,
# tagged with `campaign_participant_id` in additional_attributes so the
# C3.3 inbound listener can route replies back to the participant.
class Outreach::Engine::ConversationResolver
  class InboxMissing < StandardError; end

  def initialize(participant)
    @participant = participant
  end

  def contact
    return @participant.contact if @participant.contact_id.present?

    contact = find_or_create_contact!
    @participant.update!(contact: contact)
    contact
  end

  def conversation
    @participant.with_lock do
      @participant.reload

      if @participant.conversation_id.present?
        @participant.conversation
      else
        create_and_assign_conversation!
      end
    end
  end

  private

  def campaign
    @participant.outbound_campaign
  end

  def account
    @participant.account
  end

  def profile
    @participant.participatable
  end

  def find_or_create_contact!
    email = profile.email.to_s.downcase.strip
    existing = account.contacts.where('LOWER(email) = ?', email).first
    return existing if existing

    account.contacts.create!(
      email: email,
      name: profile.try(:owner_name).presence || profile.try(:business_name).presence || email
    )
  end

  def find_or_create_contact_inbox!(inbox)
    ContactInbox.find_or_create_by!(
      contact: contact,
      inbox: inbox,
      source_id: SecureRandom.uuid
    )
  end

  def create_and_assign_conversation!
    inbox = campaign.inbox
    raise InboxMissing, "OutboundCampaign##{campaign.id} has no inbox configured" unless inbox

    contact_inbox = find_or_create_contact_inbox!(inbox)
    conversation = create_conversation!(inbox, contact_inbox)
    @participant.update!(conversation: conversation)
    conversation
  end

  def create_conversation!(inbox, contact_inbox)
    Conversation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      additional_attributes: {
        'campaign_participant_id' => @participant.id,
        'outbound_campaign_id' => campaign.id,
        'outbound_campaign_program_key' => campaign.program_key
      }
    )
  end
end
