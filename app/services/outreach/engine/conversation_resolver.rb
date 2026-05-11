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
        assigned_conversation || create_and_assign_conversation!
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

    existing = find_existing_conversation(inbox)
    return assign_conversation!(existing) if existing

    contact_inbox = find_or_create_contact_inbox!(inbox)
    conversation = create_conversation!(inbox, contact_inbox)
    assign_conversation!(conversation)
  end

  def assigned_conversation
    conversation = Conversation.find_by(id: @participant.conversation_id)
    return conversation if conversation

    @participant.update!(conversation_id: nil)
    nil
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

  def find_existing_conversation(inbox)
    Conversation
      .where(account: account, inbox: inbox, contact: contact)
      .where("additional_attributes->>'campaign_participant_id' = ?", @participant.id.to_s)
      .order(updated_at: :desc)
      .first
  end

  def assign_conversation!(conversation)
    @participant.update!(conversation: conversation)
    conversation
  end
end
