class Influencers::LanguageDetector
  MIN_TEXT_LENGTH = 20

  # Detect language from profile content and set it on the contact.
  # Sources (in priority order): post captions, bio.
  def self.detect_and_set(profile)
    text = collect_text(profile)
    return if text.length < MIN_TEXT_LENGTH

    language = detect_language(text)
    return if language.blank?

    set_contact_locale(profile.contact, language)
    language
  end

  def self.detect_language(text)
    detector = CLD3::NNetLanguageIdentifier.new(MIN_TEXT_LENGTH, 2000)
    result = detector.find_language(text)
    return nil unless result.reliable?

    result.language.to_s
  end

  def self.collect_text(profile)
    texts = []
    texts.concat(captions_from_raw_report(profile))
    texts.concat(captions_from_apify(profile))
    texts.concat(captions_from_stored_posts(profile))
    texts << profile.bio if profile.bio.present?
    texts.compact.join("\n")
  end

  def self.set_contact_locale(contact, language)
    return if contact.blank?

    attrs = (contact.additional_attributes || {}).merge('locale' => language)
    contact.update!(additional_attributes: attrs)
  end

  # Captions from IC raw_report_data → result.instagram.post_data[].caption
  def self.captions_from_raw_report(profile)
    posts = profile.raw_report_data&.dig('result', 'instagram', 'post_data') || []
    posts.first(6).filter_map { |p| p['caption'].presence }
  end

  # Captions from Apify raw data → latestPosts[].caption
  def self.captions_from_apify(profile)
    posts = profile.apify_data&.dig('latestPosts') || []
    posts.first(6).filter_map { |p| p['caption'].presence }
  end

  # Captions from already-parsed recent_reels / recent_posts
  def self.captions_from_stored_posts(profile)
    items = Array(profile.recent_reels) + Array(profile.recent_posts)
    items.first(6).filter_map { |p| (p['caption'] || p[:caption]).presence }
  end

  private_class_method :collect_text, :set_contact_locale,
                       :captions_from_raw_report, :captions_from_apify, :captions_from_stored_posts
end
