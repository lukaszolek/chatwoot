class Outreach::InboundMessageKind
  BOUNCE_FROM_PATTERNS = [
    /mailer-daemon/i,
    /postmaster/i
  ].freeze

  BOUNCE_PATTERNS = [
    /delivery status notification/i,
    /address not found/i,
    /message not delivered/i,
    /undeliver(?:ed|able)/i,
    /wasn'?t delivered/i,
    /couldn'?t be delivered/i,
    /no such (?:mailbox|user)/i,
    /\b5\.\d\.\d\b/
  ].freeze

  AUTO_REPLY_PATTERNS = [
    /out of office/i,
    /automatic reply/i,
    /auto(?:matisch|matic)? reply/i,
    /niet aanwezig/i,
    /afwezig/i,
    /zal (?:uw|je) bericht .* beantwoorden/i,
    /binnen 24 uur/i,
    /within 24 (?:hours|hrs)/i
  ].freeze

  OPT_OUT_FIRST_LINE_PATTERNS = [
    /\Astop(?:\s+(?:aub|svp|please|pls))?[\s.!?,;:]*\z/i,
    /\Aunsubscribe(?:\s+(?:please|pls))?[\s.!?,;:]*\z/i,
    /\Auitschrijven(?:\s+(?:aub|svp))?[\s.!?,;:]*\z/i,
    /\Aafmelden(?:\s+(?:aub|svp))?[\s.!?,;:]*\z/i
  ].freeze

  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message = message
  end

  def call
    return :bounce if bounce?
    return :opt_out if opt_out?
    return :auto_reply if auto_reply?

    :reply
  end

  private

  attr_reader :message

  def bounce?
    BOUNCE_FROM_PATTERNS.any? { |pattern| from.match?(pattern) } ||
      BOUNCE_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def auto_reply?
    AUTO_REPLY_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def opt_out?
    first_meaningful_reply_line.present? &&
      OPT_OUT_FIRST_LINE_PATTERNS.any? { |pattern| first_meaningful_reply_line.match?(pattern) }
  end

  def from
    Array(message.content_attributes&.dig('email', 'from')).join(' ')
  end

  def text
    [
      message.content_attributes&.dig('email', 'subject'),
      message.content
    ].join("\n")
  end

  def reply_text
    explicit_reply_text.presence || stripped_message_content
  end

  def first_meaningful_reply_line
    reply_text.to_s.lines.map(&:strip).reject(&:blank?).first
  end

  def explicit_reply_text
    email = message.content_attributes&.fetch('email', nil) || message.content_attributes&.fetch(:email, nil)
    return unless email.is_a?(Hash)

    text_reply = nested_dig(email, 'text_content', 'reply')
    return strip_quoted_history(text_reply) if text_reply.present?

    html_reply = nested_dig(email, 'html_content', 'reply')
    return strip_quoted_history(html_to_text(html_reply)) if html_reply.present?

    nil
  end

  def stripped_message_content
    strip_quoted_history(message.content)
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
