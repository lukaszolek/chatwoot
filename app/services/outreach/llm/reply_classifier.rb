# Stub for C3.1 — real classifier lands in C4.1 (Outreach::Llm::ReplyClassifier).
# Structure and return contract are fixed here so the ClassifyReply
# executor compiles and runs in tests that stub the classifier. The
# real implementation inherits from `Enterprise::Llm::BaseAiService`
# and returns the same shape.
#
# Return contract:
#   {
#     intent_class: String,   # one of 8 classes in §4.3 of the partnerships plan
#     confidence: Float,      # 0.0-1.0
#     reasoning: String,      # optional trace for audit
#     model: String,          # LLM model identifier
#     prompt_version: String, # prompt revision marker
#     input_digest: String,   # SHA-256 of the prompt payload for dedup
#     output: Hash,           # full JSON output from the model
#     token_usage: Hash,      # { prompt_tokens:, completion_tokens: }
#     latency_ms: Integer
#   }
class Outreach::Llm::ReplyClassifier
  def initialize(participant:, conversation:, locale:)
    @participant = participant
    @conversation = conversation
    @locale = locale
  end

  def call
    raise NotImplementedError,
          'Outreach::Llm::ReplyClassifier#call lands in C4.1. ' \
          'Tests must stub this service until then.'
  end
end
