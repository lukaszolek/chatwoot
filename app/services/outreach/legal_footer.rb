class Outreach::LegalFooter
  STOP_PATTERN = /\bSTOP\b/i

  STOP_OPT_OUT = {
    'nl' => 'Als u geen verdere berichten van ons wilt ontvangen, antwoord dan met "STOP".',
    'de' => 'Wenn Sie keine weiteren Nachrichten von uns erhalten möchten, antworten Sie mit "STOP".',
    'pl' => 'Jeśli nie chcesz otrzymywać od nas kolejnych wiadomości, odpowiedz "STOP".',
    'en' => 'If you do not want to receive further messages from us, reply with "STOP".'
  }.freeze

  class << self
    def ensure_stop_opt_out(body, locale:)
      text = body.to_s
      return text if stop_opt_out_present?(text)

      [text.rstrip, stop_opt_out(locale)].reject(&:blank?).join("\n\n")
    end

    def stop_opt_out_present?(body)
      body.to_s.match?(STOP_PATTERN)
    end

    def stop_opt_out(locale)
      STOP_OPT_OUT.fetch(locale.to_s.downcase, STOP_OPT_OUT.fetch('en'))
    end
  end
end
