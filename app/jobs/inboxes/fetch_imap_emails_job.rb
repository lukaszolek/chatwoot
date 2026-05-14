require 'net/imap'

class Inboxes::FetchImapEmailsJob < MutexApplicationJob
  queue_as :scheduled_jobs

  def perform(channel, interval = 1)
    return unless should_fetch_email?(channel)

    key = format(::Redis::Alfred::EMAIL_MESSAGE_MUTEX, inbox_id: channel.inbox.id)

    with_lock(key, 5.minutes) do
      process_email_for_channel(channel, interval)
    end
  rescue *ExceptionList::IMAP_EXCEPTIONS => e
    Rails.logger.error "Authorization error for email channel - #{channel.inbox.id} : #{e.message}"
  rescue IOError, OpenSSL::SSL::SSLError, Net::IMAP::NoResponseError, Net::IMAP::BadResponseError, Net::IMAP::InvalidResponseError,
         Net::IMAP::ResponseParseError, Net::IMAP::ResponseReadError, Net::IMAP::ResponseTooLargeError => e
    Rails.logger.error "Error for email channel - #{channel.inbox.id} : #{e.message}"
  rescue LockAcquisitionError
    Rails.logger.error "Lock failed for #{channel.inbox.id}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
  end

  private

  def should_fetch_email?(channel)
    channel.imap_enabled? && !channel.reauthorization_required?
  end

  def process_email_for_channel(channel, interval)
    inbound_emails = if channel.microsoft?
                       Imap::MicrosoftFetchEmailService.new(channel: channel, interval: interval).perform
                     elsif channel.google? || channel.legacy_google?
                       Imap::GoogleFetchEmailService.new(channel: channel, interval: interval).perform
                     else
                       Imap::FetchEmailService.new(channel: channel, interval: interval).perform
                     end
    Array(inbound_emails).each do |inbound_mail|
      process_mail(inbound_mail, channel)
    end
  rescue OAuth2::Error => e
    Rails.logger.error "Error for email channel - #{channel.inbox.id} : #{e.message}"
    channel.authorization_error!
  end

  def process_mail(inbound_mail, channel)
    if inbound_mail.is_a?(Hash)
      mail = inbound_mail[:mail]
      direction = inbound_mail[:direction] || :incoming
    else
      mail = inbound_mail
      direction = :incoming
    end

    Imap::ImapMailbox.new.process(mail, channel, direction: direction)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
    Rails.logger.error("
      #{channel.provider} Email dropped: #{mail&.from} and message_source_id: #{mail&.message_id}")
  end
end
