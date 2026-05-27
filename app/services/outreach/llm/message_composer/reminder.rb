# 7-day follow-up. Knows the previous outreach (visible in conversation
# history) so can reference "I sent you a note last week" without
# repeating the entire offer.
class Outreach::Llm::MessageComposer::Reminder < Outreach::Llm::MessageComposer::Base
  SLOT = 'reminder'.freeze
  PROMPT_VERSION = 'outreach.compose_reminder.v1'.freeze

  private

  def slot_instruction
    <<~TEXT.strip
      SLOT INSTRUCTION — REMINDER (7 days after first touch, no reply yet):
        - This is NOT the first email. Never use intro_seed as a body
          template. intro_seed can only inform facts such as commissions
          and terminology.
        - Acknowledge the prior message gently ("ostatni mail", "previous
          note", "letzte Nachricht") — assume it landed in spam or got
          buried.
        - Use the conversation history / last outgoing message as context.
          If no previous outgoing email is visible in history, still write
          a short follow-up, not a new intro.
        - Compress the offer to a 2-3 sentence summary using KNOWLEDGE →
          program_rules. Do not repeat the full intro.
        - Do not reintroduce Łukasz/Framky with the full first-touch
          paragraph. Do not repeat the full product paragraph about
          fine-art paper, pigment inks, PANTONE coverage, or framing.
        - Include only one low-friction CTA.
        - Single-word reply CTA ("yes" / "not now" / "ping me later").
        - Length: ≤ 7 sentences.
    TEXT
  end
end
