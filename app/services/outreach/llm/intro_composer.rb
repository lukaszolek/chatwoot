# Generates ONLY the personal opener sentence for an intro email.
# The rest of the body (value prop, bullet list with percentages,
# signature) is fixed copy maintained in the blueprint YAML; we don't
# let the LLM rewrite the offer.
#
# Inputs:
#   - participant (+ resolved photographer profile)
#   - website snippet (crawled content from photographer-directory;
#     optional — when missing LLM falls back to profile cues)
#   - locale (drives formality: de/fr very-formal, pl/en/it/cs/ro
#     moderate, da/nl/es/fi relaxed)
#
# Output: { opener: String } — 1–2 sentences, ≤ 240 chars, no
# superlatives. The caller (SendTemplate executor) string-replaces
# `{{personal_opener}}` in the Liquid-rendered template with this.
#
# Safety: on any LLM error we return a locale-appropriate neutral
# fallback so the mail still goes out. The intro never blocks on LLM.
class Outreach::Llm::IntroComposer
  PROMPT_VERSION = 'outreach.compose_intro.v3'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are Łukasz Olek, founder of Framky. Writing personal outreach
    to a photographer about our partnership programme.

    Your ONLY job: produce a personal opener (1–2 sentences, max 240
    chars) that I'll drop into the first paragraph of the email. The
    rest of the email is already written — you don't touch offer,
    bullets, percentages, signature.

    RULES
    - Ground the opener in a concrete detail from the photographer's
      website snippet or profile: specific style trait (reportażowy,
      intymny, czarno-biały, light-driven), niche (śluby plenerowe,
      newborn, corporate portraits), a phrase lifted from their site,
      an aesthetic cue. No "I love your work" / "your photos are
      amazing" — lazy and generic.
    - First person, warm, matter-of-fact, no superlatives.
    - When the website snippet is missing/thin, lean on profile cues
      (business_name, instagram_handle, city) — and do NOT claim to
      have read the site.
    - Match the locale's register:
      - de / fr → very formal, Sie/Vous
      - pl / en / it / cs / ro → moderate, Ty / first-name
      - da / nl / es / fi → relaxed, casual
    - Gender agreement: detect from first name; use the matching
      forms (Polish "byłbyś" vs "byłabyś"). Gender-neutral when
      uncertain.
    - No greetings (no "Cześć", no "Hi", no "Hallo") — the template
      already has the salutation. Just the opener body.
    - No trailing signoff. Just the opener sentences.

    OUTPUT
    Return STRICT JSON:
      { "opener": "…", "reasoning": "one-sentence cue note" }

    Return raw JSON only.
  PROMPT

  LOCALE_FALLBACKS = {
    'pl' => 'Wpadłem na Twoje portfolio — widać, że podchodzisz do kadru z uwagą.',
    'en' => 'Came across your portfolio — the care in how you frame a shot stood out.',
    'de' => 'Ich bin auf Ihr Portfolio gestoßen — der sorgfältige Bildaufbau ist sofort erkennbar.',
    'fr' => 'Je suis tombé sur votre portfolio — votre soin du cadre saute aux yeux.',
    'it' => 'Ho trovato il tuo portfolio — l’attenzione al frame si vede subito.',
    'es' => 'Vi tu portafolio — se nota el cuidado en el encuadre.',
    'nl' => 'Kwam je werk tegen — de zorg voor het kader valt direct op.'
  }.freeze
  DEFAULT_FALLBACK_LOCALE = 'en'.freeze

  def self.fallback_opener(locale)
    LOCALE_FALLBACKS[locale.to_s] || LOCALE_FALLBACKS[DEFAULT_FALLBACK_LOCALE]
  end

  def initialize(participant:, locale: nil)
    @participant = participant
    @locale = locale
  end

  def call
    ctx = LlmFormatter::PhotographerPartnerLlmFormatter.new(@participant).format
    user_prompt = build_user_prompt(ctx)

    result = client.ask_json!(
      model: client.compose_model,
      system: SYSTEM_PROMPT,
      user: user_prompt,
      temperature: 0.5
    )
    parsed = result.fetch(:parsed)
    opener = parsed['opener'].to_s.strip

    build_success(opener, parsed, result, user_prompt)
  rescue Outreach::Llm::Client::LlmError => e
    Rails.logger.warn("[outreach.intro_composer] llm_error=#{e.class}: #{e.message.truncate(200)}")
    build_fallback(reason: "llm_error:#{e.class}")
  end

  private

  def client
    @client ||= Outreach::Llm::Client.new
  end

  def build_user_prompt(ctx)
    locale = resolve_locale(ctx)
    snippet = ctx[:website_snippet]
    <<~USER
      Locale: #{locale}
      Photographer profile: #{ctx[:profile]}

      #{format_website_snippet(snippet)}
    USER
  end

  def resolve_locale(ctx)
    @locale || ctx[:locale] || DEFAULT_FALLBACK_LOCALE
  end

  def format_website_snippet(snippet)
    return 'Photographer website crawl: (no content available — do not claim to have read the site)' if snippet.blank?

    [
      "Photographer website snippet (source: #{snippet[:source_url]}):",
      snippet[:page_type] && "Page type: #{snippet[:page_type]}",
      snippet[:title] && "Title: #{snippet[:title]}",
      'Content excerpt:',
      snippet[:excerpt]
    ].compact.join("\n")
  end

  def build_success(opener, parsed, result, user_prompt)
    {
      opener: opener,
      reasoning: parsed['reasoning'].to_s,
      model: client.compose_model,
      prompt_version: PROMPT_VERSION,
      input_digest: Digest::SHA256.hexdigest(user_prompt),
      output: parsed,
      token_usage: result[:token_usage],
      latency_ms: result[:latency_ms],
      fallback: false
    }
  end

  def build_fallback(reason:)
    locale = @locale || (@participant.metadata || {})['locale'].presence ||
             @participant.participatable.try(:preferred_language).presence ||
             DEFAULT_FALLBACK_LOCALE
    {
      opener: self.class.fallback_opener(locale),
      reasoning: reason,
      model: client.compose_model,
      prompt_version: PROMPT_VERSION,
      input_digest: nil,
      output: { 'fallback' => reason },
      token_usage: {},
      latency_ms: nil,
      fallback: true
    }
  end
end
