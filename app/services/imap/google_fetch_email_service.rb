class Imap::GoogleFetchEmailService < Imap::BaseFetchEmailService
  GMAIL_SENT_FOLDER = '[Gmail]/Sent Mail'.freeze

  def fetch_emails
    return [] unless authenticatable?

    inbox_mails = fetch_folder('INBOX', :incoming)
    sent_mails = fetch_folder(GMAIL_SENT_FOLDER, :outgoing)

    inbox_mails + sent_mails
  end

  private

  def authenticatable?
    return true if oauth_authentication?

    channel.imap_password.present?
  end

  def oauth_authentication?
    channel.google? && channel.provider_config.is_a?(Hash) && channel.provider_config['access_token'].present?
  end

  def authentication_type
    oauth_authentication? ? 'XOAUTH2' : 'PLAIN'
  end

  def imap_password
    if oauth_authentication?
      Google::RefreshOauthTokenService.new(channel: channel).access_token
    else
      channel.imap_password
    end
  end

  def fetch_folder(folder, direction)
    select_folder(imap_client, folder)
    fetch_mail_for_channel(direction: direction)
  rescue Net::IMAP::NoResponseError => e
    Rails.logger.warn "[IMAP::GOOGLE_FETCH] Could not select folder #{folder} for #{channel.email}: #{e.message}"
    []
  end

  def build_imap_client
    imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: true)
    imap.authenticate(authentication_type, channel.imap_login, imap_password)
    imap
  end
end
