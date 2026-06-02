# Formats a CampaignParticipant + its PhotographerPartnerProfile + the
# recent messages on its Conversation into prompt-ready structured text.
#
# Output is a Hash with stable keys so prompts can opt in to only what
# they need (intro composer doesn't need the reply thread; classifier
# does):
#
#   {
#     profile: "Alex Example, Studio Alex, https://alex.photo, …",
#     website_snippet: { title:, excerpt:, page_type:, source_url: } or nil,
#     last_intro_summary: "Subject: …\nBody: …",
#     reply_text: "Tak, chcę dołączyć!",
#     conversation_history: ["OUT: …", "IN: …", …],
#     locale: "pl"
#   }
class LlmFormatter::PhotographerPartnerLlmFormatter
  MAX_HISTORY_MESSAGES = 6
  MAX_MESSAGE_CHARS = 1500

  def initialize(participant)
    @participant = participant
    @conversation = participant.conversation
  end

  def format
    {
      profile: format_profile,
      website_snippet: fetch_website_snippet,
      last_intro_summary: last_outreach_message_summary,
      reply_text: last_incoming_message&.truncate(MAX_MESSAGE_CHARS),
      conversation_history: conversation_history,
      locale: resolve_locale
    }
  end

  private

  def profile_model
    @participant.participatable
  end

  def format_profile
    p = profile_model
    [
      p.try(:owner_name),
      p.try(:business_name),
      p.try(:website),
      p.try(:country_code),
      p.try(:instagram_handle) && "IG @#{p.instagram_handle}"
    ].compact.reject { |s| s.to_s.empty? }.join(' · ')
  end

  def conversation_history
    return [] unless @conversation

    @conversation.messages
                 .where(message_type: %i[incoming outgoing], private: false)
                 .order(created_at: :desc)
                 .limit(MAX_HISTORY_MESSAGES)
                 .reverse
                 .map do |message|
      content = message.incoming? ? formatted_incoming_content(message) : message.content.to_s
      "#{message.incoming? ? 'IN' : 'OUT'}: #{content.truncate(MAX_MESSAGE_CHARS)}"
    end
  end

  def last_outreach_message_summary
    return nil unless @conversation

    m = @conversation.messages.where(message_type: :outgoing, private: false).order(created_at: :desc).first
    return nil unless m

    subject = m.additional_attributes.to_h.dig('outreach', 'subject')
    "Subject: #{subject}\nBody: #{m.content.to_s.truncate(MAX_MESSAGE_CHARS)}".strip
  end

  def last_incoming_message
    return nil unless @conversation

    message = @conversation.messages.where(message_type: :incoming, private: false).order(created_at: :desc).first
    return nil unless message

    formatted_incoming_content(message)
  end

  def resolve_locale
    (@participant.metadata || {})['locale'].presence ||
      profile_model.try(:preferred_language).presence ||
      (@participant.outbound_campaign.config || {})['default_locale'].presence ||
      'en'
  end

  def fetch_website_snippet
    Outreach::Llm::WebsiteSnippet.for(profile_model)
  end

  def formatted_incoming_content(message)
    explicit_reply_text(message).presence || strip_quoted_history(message.content)
  end

  def explicit_reply_text(message)
    email = message.content_attributes&.fetch('email', nil) || message.content_attributes&.fetch(:email, nil)
    return unless email.is_a?(Hash)

    text_reply = nested_dig(email, 'text_content', 'reply')
    return strip_quoted_history(text_reply) if text_reply.present?

    html_reply = nested_dig(email, 'html_content', 'reply')
    return strip_quoted_history(html_to_text(html_reply)) if html_reply.present?

    nil
  end

  def strip_quoted_history(value)
    value.to_s
         .split(/\n-{2,}\s*Original Message\s*-{2,}/i, 2).first
         .split(/\nOn .+wrote:\s*/i, 2).first
         .split(/\nOp .+schreef.*:\s*/i, 2).first
         .split(/\nW dniu .+napisa.*:\s*/i, 2).first
         .split(/\nVan:|\nFrom:|\nOd:/i, 2).first
         .strip
  end

  def nested_dig(hash, *keys)
    keys.reduce(hash) do |value, key|
      break unless value.is_a?(Hash)

      value[key] || value[key.to_sym]
    end
  end

  def html_to_text(html)
    ActionView::Base.full_sanitizer.sanitize(html.to_s)
  end
end
