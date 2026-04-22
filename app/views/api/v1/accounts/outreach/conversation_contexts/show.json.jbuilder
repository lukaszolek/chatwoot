json.campaign do
  json.id @campaign.id
  json.name @campaign.name
  json.program_key @campaign.program_key
  json.status @campaign.status
end
json.participant do
  json.id @participant.id
  json.current_stage_key @participant.current_stage_key
  json.stage_entered_at @participant.stage_entered_at&.to_i
  json.next_action_at @participant.next_action_at&.to_i
  json.last_outbound_at @participant.last_outbound_at&.to_i
  json.last_inbound_at @participant.last_inbound_at&.to_i
  json.paused @participant.paused
  json.metadata @participant.metadata
end
if @stage
  json.stage do
    json.key @stage.key
    json.on_enter_action @stage.on_enter_action
    json.position @stage.position
    json.auto_advance_after_hours @stage.auto_advance_after_hours
    json.next_stage_key @stage.next_stage_key
  end
end
if @profile
  json.profile do
    json.partial! 'api/v1/models/photographer_partner_profile', formats: [:json], resource: @profile
  end
end
