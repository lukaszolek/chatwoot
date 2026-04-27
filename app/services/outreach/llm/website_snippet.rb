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
  MAX_CHARS = 1800

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
      excerpt: clip(page.content_markdown.to_s),
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

    pairs.min_by { |page, type| ranking_key(page, type) }&.first
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

  def ranking_key(page, classified_type)
    priority_index = PAGE_TYPE_PRIORITY.index(classified_type) || PAGE_TYPE_PRIORITY.size
    [priority_index, -page.content_markdown.to_s.length]
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

  def clip(markdown)
    return nil if markdown.blank?

    # Strip markdown noise that burns tokens without adding signal,
    # and drop control/escape chars that confuse downstream LLM
    # gateways (EUrouter returned 400 on raw crawl markdown that
    # contained escaped underscores and image URLs).
    text = markdown
           .gsub(/!\[[^\]]*\]\([^)]*\)/, '')  # images
           .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1') # links → label
           .gsub(/^#+\s*/m, '')                # heading markers
           .gsub(%r{https?://\S+}, '')         # bare URLs
           .gsub(/\\([_*])/, '\1')             # un-escape markdown underscores/asterisks
           .gsub(/[\u0000-\u001F]/) { |c| c == "\n" ? "\n" : ' ' } # strip control chars (keep newlines)
           .gsub(/[ \t]{2,}/, ' ')             # collapse runs of spaces
           .gsub(/\n{3,}/m, "\n\n")            # collapse blank lines
           .strip
    text.length > MAX_CHARS ? "#{text[0, MAX_CHARS]}…" : text
  end
end
