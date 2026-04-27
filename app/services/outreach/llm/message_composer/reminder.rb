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
        - Acknowledge the prior message gently ("ostatni mail", "previous
          note", "letzte Nachricht") — assume it landed in spam or got
          buried.
        - Compress the offer to a 2-3 sentence summary using KNOWLEDGE →
          program_rules. Do not repeat the full intro.
        - Single-word reply CTA ("yes" / "not now" / "ping me later").
        - Length: ≤ 7 sentences.
    TEXT
  end
end
