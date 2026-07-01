# Fetches a compact, LLM-ready snippet of a photographer's website from
# the crawled content that photographer-directory already has stored in
# its `urls` + `pages` tables. Prefers pages the directory already
# classified as about/portfolio/homepage because those carry the
# strongest signal (voice, niche, style) with the least noise (prices,
# contact forms, blog filler).
#
# Contract: returns a Hash { title:, excerpt:, page_type:, source_url: }
# or nil if nothing usable. Callers (IntroComposer) treat nil as
# "fall back to generic opener" — never a hard error.
#
# Read path uses the chatwoot read-only role which has SELECT on urls +
# pages (see photographer-directory/packages/database/src/scripts/
# setup-chatwoot-outreach-role.ts).
class Outreach::Llm::WebsiteSnippet
  PAGE_TYPE_PRIORITY = %w[about portfolio gallery homepage service other].freeze
  PERSONAL_PAGE_TYPE_PRIORITY = %w[homepage about service portfolio gallery other].freeze
  MAX_CHARS = 1800
  HIGH_INTENT_PATTERNS = [
    /wedding|weddings|marriage|mariage|mariages|trouw|bruiloft|hochzeit|hochzeiten/i,
    /family|families|famille|familles|gezin|gezins|familie|familieshoots/i,
    /newborn|nouveau[\s-]?né|nouveau[\s-]?nés|babyshoot|b[ée]b[ée]/i,
    /maternity|grossesse|zwangerschap|pregnancy/i,
    /children|kids|kinderen|enfants/i,
    /couple|couples|koppel|koppels/i,
    /boudoir/i
  ].freeze
  MEDIUM_INTENT_PATTERNS = [
    /portrait|portraits/i
  ].freeze
  LOW_FIT_PATTERNS = [
    /corporate|entreprise|business|bedrijfs|bedrijf|headshot|linkedin/i,
    /immobilier|real estate|realestate|vastgoed|interieur|interior|architecture/i,
    /produit|product|packshot|e-?commerce/i,
    /iris/i,
    /video|film|visite virtuelle|virtual tour|photo booth|photobooth|borne photo|fotobudk/i,
    /passport|identity photo|photos? d'identité|documentfoto/i,
    /art print|fine art print|tirage d'art|limited edition|oeuvre|œuvre|kunstwerk/i,
    /tirages?\s+encadr[ée]s?|framed prints?|wall art shop|prints? for sale|tableaux?\s+photo/i
  ].freeze

  def self.for(profile)
    new(profile).fetch
  end

  def initialize(profile)
    @profile = profile
  end

  def fetch
    domain = extract_domain(@profile.try(:website))
    return nil if domain.blank?

    page = pick_best_page(domain)
    return nil unless page

    {
      title: page.title.to_s.strip.presence,
      excerpt: build_excerpt(page.content_markdown.to_s),
      page_type: page.try(:read_attribute, :page_type)&.to_s,
      source_url: "https://#{domain}"
    }.compact
  rescue ActiveRecord::StatementInvalid,
         ActiveRecord::ConnectionNotEstablished,
         ActiveRecord::DatabaseConnectionError,
         PG::ConnectionBad => e
    # Missing grants or secondary DB / VPN down — fail soft, no personalization.
    Rails.logger.warn("[outreach.website_snippet] #{e.class}: #{e.message.truncate(200)}")
    nil
  end

  private

  def extract_domain(url)
    return nil if url.blank?

    url.to_s.strip.sub(%r{^https?://}, '').sub(/^www\./, '').split('/', 2).first.presence
  end

  def pick_best_page(domain)
    url_rows = PhotographerDirectory::Url.where(domain: domain).to_a
    return nil if url_rows.empty?

    pairs = build_scored_page_pairs(url_rows)
    return nil if pairs.empty?

    best_page_from_pairs(pairs)
  end

  def build_scored_page_pairs(url_rows)
    pages_by_url = load_pages_by_url_id(url_rows.map(&:id))
    return [] if pages_by_url.empty?

    url_rows.filter_map do |url|
      page = pages_by_url[url.id]
      next nil unless page_has_content?(page)

      [page, url.try(:read_attribute, :classified_type).to_s]
    end
  end

  def page_has_content?(page)
    page&.content_markdown.to_s.strip.length.to_i > 80
  end

  def best_page_from_pairs(pairs)
    positive_context = pairs.any? { |page, _| positive_signal_score(page.content_markdown.to_s).positive? }
    pairs.min_by { |page, type| ranking_key(page, type, positive_context: positive_context) }&.first
  end

  def ranking_key(page, classified_type, positive_context:)
    priority = page_type_priority(positive_context)
    priority_index = priority.index(classified_type) || priority.size
    [*category_penalty(page.content_markdown.to_s, positive_context: positive_context), priority_index, -page.content_markdown.to_s.length]
  end

  def page_type_priority(positive_context)
    positive_context ? PERSONAL_PAGE_TYPE_PRIORITY : PAGE_TYPE_PRIORITY
  end

  def category_penalty(text, positive_context:)
    return [0, 0, 0, 0, 0] unless positive_context

    positive_score = positive_signal_score(text)
    negative_score = negative_signal_score(text)
    [
      negative_score.positive? && positive_score.zero? ? 1 : 0,
      positive_score.zero? ? 1 : 0,
      negative_score.positive? ? 1 : 0,
      -positive_score,
      negative_score
    ]
  end

  def positive_signal_score(text)
    weighted_keyword_score(text, HIGH_INTENT_PATTERNS, weight: 3) +
      weighted_keyword_score(text, MEDIUM_INTENT_PATTERNS, weight: 1)
  end

  def negative_signal_score(text)
    weighted_keyword_score(text, LOW_FIT_PATTERNS, weight: 1)
  end

  def weighted_keyword_score(text, patterns, weight:)
    patterns.sum { |pattern| text.match?(pattern) ? weight : 0 }
  end

  def load_pages_by_url_id(url_ids)
    return {} if url_ids.empty?

    # Avoid .where(url_id: ...) which on some chatwoot secondary DB
    # setups collides with calculation/pluck monkey-patches. Fetch each
    # page's first row via individual queries and aggregate. 20 URLs is
    # the typical crawl depth per domain so this stays cheap.
    url_ids.each_with_object({}) do |uid, acc|
      rec = PhotographerDirectory::Page.where(url_id: uid).first
      acc[uid] = rec if rec
    end
  end

  def build_excerpt(markdown)
    text = normalize_markdown(markdown)
    return nil if text.blank?

    text = drop_low_fit_lines(text) if positive_signal_score(text).positive?
    truncate_excerpt(text)
  end

  def normalize_markdown(markdown)
    return nil if markdown.blank?

    # Strip markdown noise that burns tokens without adding signal,
    # and drop control/escape chars that confuse downstream LLM
    # gateways (EUrouter returned 400 on raw crawl markdown that
    # contained escaped underscores and image URLs).
    markdown
      .gsub(/!\[[^\]]*\]\([^)]*\)/, '')  # images
      .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1') # links → label
      .gsub(/^#+\s*/m, '')                # heading markers
      .gsub(%r{https?://\S+}, '')         # bare URLs
      .gsub(/\\([_*])/, '\1')             # un-escape markdown underscores/asterisks
      .gsub(/[\u0000-\u001F]/) { |c| c == "\n" ? "\n" : ' ' } # strip control chars (keep newlines)
      .gsub(/[ \t]{2,}/, ' ')             # collapse runs of spaces
      .gsub(/\n{3,}/m, "\n\n")            # collapse blank lines
      .strip
  end

  def drop_low_fit_lines(text)
    filtered = text.each_line.reject do |line|
      line_text = line.to_s.strip
      next false if line_text.blank?

      negative_signal_score(line_text).positive? && positive_signal_score(line_text).zero?
    end.join

    filtered.presence || text
  end

  def truncate_excerpt(text)
    text.length > MAX_CHARS ? "#{text[0, MAX_CHARS]}…" : text
  end
end
