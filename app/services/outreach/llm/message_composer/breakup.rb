# 14-day "last note from me" message. Door open, no pressure. Uses the
# conversation history if any to acknowledge their silence as their
# answer.
class Outreach::Llm::MessageComposer::Breakup < Outreach::Llm::MessageComposer::Base
  SLOT = 'breakup'.freeze
  PROMPT_VERSION = 'outreach.compose_breakup.v1'.freeze

  private

  def slot_instruction
    <<~TEXT.strip
      SLOT INSTRUCTION — BREAKUP (14 days after intro, still no reply):
        - "OK — I'll stop following up, this is the last one from me."
        - Leave the door open with a concrete future hook ("if a client
          ever asks where to print on a wall, reply to this email").
        - Friendly close ("best of luck with the work").
        - Length: ≤ 5 sentences.
        - DO NOT use guilt-trip framing or any sales urgency.
    TEXT
  end
end
