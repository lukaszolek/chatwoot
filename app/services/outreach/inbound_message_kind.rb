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

  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message = message
  end

  def call
    return :bounce if bounce?
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

  def from
    Array(message.content_attributes&.dig('email', 'from')).join(' ')
  end

  def text
    [
      message.content_attributes&.dig('email', 'subject'),
      message.content
    ].join("\n")
  end
end
