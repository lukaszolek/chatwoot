# Terminal executor: pauses the participant. Reached when a pipeline
# ends successfully (signup, explicit decline, breakup, spam).
class Outreach::Engine::Executors::Terminal < Outreach::Engine::Executors::Base
  def call
    pause_terminal!(reason: "terminal:#{stage.key}")
  end
end
