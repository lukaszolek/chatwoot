require 'net/imap'

# Shared IMAP connection helpers for Gmail mailboxes, used by both the read path
# (Conversations::MailboxSyncService) and the write path (Conversations::GmailArchiveJob).
module Conversations::GmailImap
  module_function

  def build_client(channel)
    if oauth?(channel)
      access_token = Google::RefreshOauthTokenService.new(channel: channel).access_token
      imap = Net::IMAP.new('imap.gmail.com', port: 993, ssl: true)
      imap.authenticate('XOAUTH2', channel.imap_login.presence || channel.email, access_token)
    elsif channel.imap_password.present?
      imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: true)
      imap.authenticate('PLAIN', channel.imap_login, channel.imap_password)
    else
      return nil
    end
    imap
  end

  def safe_logout(imap)
    return unless imap

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end

  def oauth?(channel)
    channel.provider == 'google' && channel.provider_config.is_a?(Hash) && channel.provider_config['access_token'].present?
  end
end
