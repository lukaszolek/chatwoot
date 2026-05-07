class Imap::ImapMailbox
  include MailboxHelper
  include IncomingEmailValidityHelper
  attr_accessor :channel, :account, :inbox, :conversation, :processed_mail, :direction

  FALLBACK_CONVERSATION_PATTERN = %r{account/(\d+)/conversation/([a-zA-Z0-9-]+)@}

  def process(mail, channel, direction: :incoming)
    @inbound_mail = mail
    @channel = channel
    @direction = direction
    load_account
    load_inbox
    decorate_mail

    Rails.logger.info(
      "Processing #{direction} Email from: #{@processed_mail.original_sender} : " \
      "inbox #{@inbox.id} : message_id #{@processed_mail.message_id}"
    )

    # Skip processing email if it belongs to any of the edge cases
    return unless valid_email_for_processing?

    find_or_create_contact
    return if @contact.blank?

    ActiveRecord::Base.transaction do
      find_or_create_conversation
      create_message(direction: @direction, sender: message_sender, created_at: email_sent_at)
      add_attachments_to_message
    end
  end

  def email_sent_at
    @inbound_mail.date&.to_time
  rescue StandardError
    nil
  end

  private

  def load_account
    @account = @channel.account
  end

  def load_inbox
    @inbox = @channel.inbox
  end

  def decorate_mail
    @processed_mail = MailPresenter.new(@inbound_mail, @account)
  end

  def valid_email_for_processing?
    if outgoing?
      return false if chatwoot_self_sent?
      return false unless @account.active?

      true
    else
      incoming_email_from_valid_email?
    end
  end

  def outgoing?
    @direction == :outgoing
  end

  def chatwoot_self_sent?
    return false if @processed_mail.message_id.blank?

    Imap::BaseFetchEmailService::CHATWOOT_MESSAGE_ID_PATTERN.match?(@processed_mail.message_id)
  end

  def find_conversation_by_in_reply_to
    return if in_reply_to.blank?

    message = @inbox.messages.find_by(source_id: in_reply_to)
    if message.nil?
      @inbox.conversations.find_by("additional_attributes->>'in_reply_to' = ?", in_reply_to)
    else
      @inbox.conversations.find(message.conversation_id)
    end
  end

  def find_conversation_by_reference_ids
    return if @inbound_mail.references.blank?

    message = find_message_by_references
    if message.present?
      conversation = @inbox.conversations.find_by(id: message.conversation_id)
      return conversation if conversation.present?
    end

    # FALLBACK_PATTERN use to find a conversation that is started by an agent (no incoming message yet)
    conversation_id = find_conversation_by_references
    @inbox.conversations.find_by(uuid: conversation_id) if conversation_id.present?
  end

  def in_reply_to
    @processed_mail.in_reply_to
  end

  def find_conversation_by_references
    references = Array.wrap(@inbound_mail.references)
    references.each do |message_id|
      match = FALLBACK_CONVERSATION_PATTERN.match(message_id)

      return match[2] if match.present?
    end
  end

  def find_message_by_references
    message_to_return = nil

    references = Array.wrap(@inbound_mail.references)

    references.each do |message_id|
      message = @inbox.messages.find_by(source_id: message_id)
      message_to_return = message if message.present?
    end
    message_to_return
  end

  def find_conversation_by_reverse_references
    return if @processed_mail.message_id.blank?

    reply = @inbox.messages.find_by("content_attributes->'email'->>'in_reply_to' = ?", @processed_mail.message_id)
    return @inbox.conversations.find_by(id: reply.conversation_id) if reply.present?

    ref_match = @inbox.messages.where("content_attributes->'email'->'references' IS NOT NULL")
                      .where("content_attributes->'email'->>'references' LIKE ?", "%#{@processed_mail.message_id}%").first
    @inbox.conversations.find_by(id: ref_match.conversation_id) if ref_match.present?
  end

  def find_or_create_conversation
    found = find_conversation_by_in_reply_to || find_conversation_by_reference_ids
    found ||= find_conversation_by_reverse_references if outgoing?
    @conversation = found || ::Conversation.create!(new_conversation_attributes)
  end

  def new_conversation_attributes
    {
      account_id: @account.id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      status: outgoing? ? :resolved : :open,
      additional_attributes: {
        source: outgoing? ? 'email_sent' : 'email',
        in_reply_to: in_reply_to,
        auto_reply: @processed_mail.auto_reply?,
        mail_subject: @processed_mail.subject,
        initiated_at: {
          timestamp: Time.now.utc
        }
      }
    }
  end

  def find_or_create_contact
    contact_email = contact_email_for_direction
    return if contact_email.blank?

    @contact = @inbox.contacts.from_email(contact_email)
    if @contact.present?
      @contact_inbox = ContactInbox.find_by(inbox: @inbox, contact: @contact)
    else
      create_contact_for(contact_email)
    end
  end

  def contact_email_for_direction
    outgoing? ? recipient_email : @processed_mail.original_sender
  end

  def recipient_email
    candidates = Array.wrap(@inbound_mail.to).map(&:to_s).map(&:downcase)
    candidates += Array.wrap(@inbound_mail.cc).map(&:to_s).map(&:downcase)
    candidates.reject! { |e| e == @channel.email.to_s.downcase }
    candidates.first
  end

  def create_contact_for(email)
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: email,
      inbox: @inbox,
      contact_attributes: {
        name: identify_contact_name_for(email),
        email: email,
        additional_attributes: { source_id: "email:#{processed_mail.message_id}" }
      }
    ).perform

    @contact = @contact_inbox.contact
    Rails.logger.info "[ImapMailbox] Contact created with ID: #{@contact.id} for inbox with ID: #{@inbox.id}"
  end

  def identify_contact_name_for(email)
    if outgoing?
      recipient_name || email.split('@').first
    else
      processed_mail.sender_name || email.split('@').first
    end
  end

  def recipient_name
    to_field = @inbound_mail[:to]
    return nil unless to_field

    address = Mail::Address.new(to_field.value)
    address.name
  rescue StandardError
    nil
  end

  def message_sender
    if outgoing?
      sender_email = @processed_mail.from&.first
      user = sender_email.present? ? @account.users.from_email(sender_email) : nil
      user || @account.administrators.first
    else
      @contact
    end
  end
end
