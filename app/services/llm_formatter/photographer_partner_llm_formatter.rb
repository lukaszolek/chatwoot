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
                 .map { |m| "#{m.incoming? ? 'IN' : 'OUT'}: #{m.content.to_s.truncate(MAX_MESSAGE_CHARS)}" }
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

    @conversation.messages.where(message_type: :incoming, private: false).order(created_at: :desc).first&.content
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
end
