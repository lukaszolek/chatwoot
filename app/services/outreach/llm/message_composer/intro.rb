# First-touch outreach. No conversation history (this is the very first
# message). Heavy reliance on the website snippet for personalization.
class Outreach::Llm::MessageComposer::Intro < Outreach::Llm::MessageComposer::Base
  SLOT = 'intro'.freeze
  PROMPT_VERSION = 'outreach.compose_intro.v1'.freeze

  private

  # rubocop:disable Metrics/MethodLength
  def slot_instruction
    <<~TEXT.strip
      SLOT INSTRUCTION — INTRO (first touch):

      PRIORITY 1 — intro_seed is the absolute authority for first-touch copy.
        If KNOWLEDGE contains an `intro_seed` document, COPY ITS BULLETS AND
        BODY PARAGRAPHS VERBATIM. The seed represents an explicit business
        decision about what this campaign promises — it OVERRIDES open_issues
        and any legalistic ambiguity. Do not rephrase the bullets. Do not
        soften concrete percentages ("20% prowizji", "25% rabat dla klienta",
        "2% bezterminowo od poleconych fotografów") into vague phrases like
        "atrakcyjna prowizja". The 2% second-level (partner-refers-partner)
        bullet is load-bearing — keep it visible, do not collapse it into
        the first-level commission line.

        Change ONLY:
          * The opener (first sentence, before "Cześć" or company intro) —
            anchor it in one concrete detail from the website snippet (a style
            trait, niche, a phrase lifted from the site). If the snippet is
            thin, lean on profile cues (business name, IG handle, city)
            WITHOUT claiming you read the site.
          * The salutation name to match {{first_name}}, gender-agreement
            forms (Polish byłbyś/byłabyś etc.) to match gender from first name.
          * Recipient number agreement is mandatory. If the profile, business
            name, snippet, or salutation indicates a duo, married couple,
            two named photographers, or a team, keep plural address
            consistently throughout the entire email: opener, body, bullets,
            CTA, legal footer, and opt-out. Never switch from a plural opener
            to singular benefits or singular CTA later in the same draft.

      PRIORITY 2 — tone and voice rules (KNOWLEDGE → copywriting, tone).
        Apply the cold-email principles: write like a peer, every sentence
        earns its place, no corporate buzzwords, no "uwielbiam Twoje zdjęcia"
        / "I love your work" / "I hope this finds you well".

      PRIORITY 3 — open_issues is for operators and for REPLY composing, NOT
        for first-touch. For intro, ignore open_issues constraints that would
        contradict the seed — the seed is the explicit "we've accepted this
        legal ambiguity for outreach purposes" decision.

      PRIORITY 4 — Subject line: 2-4 words, lowercase, boring/internal
        (from KNOWLEDGE → copywriting). No first name, no urgency, no
        percentages, no emoji.
        The subject must explain the offer category first, not the
        photographer's artistic style. Prefer safe, concrete commercial
        shapes such as:
          - "galerie ścienne dla klientów"
          - "prints voor uw klanten"
          - "galeries murales"
          - "wall galleries for clients"
        You MAY lightly personalise the subject only when the category is
        explicit and directly relevant to the offer (for example portraits,
        weddings, families, vastgoed/real estate). Good pattern:
          - "<category> + prints / galleries / wall art"
        Avoid metaphorical, poetic, or vague subjects such as
        "moments on the wall", "kadry na ścianie", "souvenirs sur vos murs".
        Never use fragile details from the site unless they are unambiguous
        in the snippet. If unsure, fall back to the safer generic subject
        about prints/galleries for clients.

      If there is NO intro_seed document, improvise within copywriting rules.
      Length cap: ≤ 150 words (the seed drives length; don't pad, don't
      over-compress).
    TEXT
  end
  # rubocop:enable Metrics/MethodLength
end
