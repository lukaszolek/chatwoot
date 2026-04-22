json.id resource.id
json.campaign_participant_id resource.campaign_participant_id
json.conversation_id resource.conversation_id
json.subject resource.subject
json.body resource.body
json.template_slot resource.template_slot
json.locale resource.locale
json.status resource.status
json.iteration_count resource.iteration_count
json.reviewed_at resource.reviewed_at&.to_i
json.reviewed_by_user_id resource.reviewed_by_user_id
json.assigned_user_id resource.assigned_user_id
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i

if resource.campaign_llm_decision_id.present?
  decision = resource.campaign_llm_decision
  json.llm_decision do
    json.id decision.id
    json.decision_type decision.decision_type
    json.model decision.model
    json.confidence decision.confidence
    json.routed_to decision.routed_to
    json.output decision.output
  end
end

json.participant do
  p = resource.campaign_participant
  json.id p.id
  json.current_stage_key p.current_stage_key
  if p.participatable.is_a?(PhotographerPartnerProfile)
    json.profile do
      json.partial! 'api/v1/models/photographer_partner_profile', formats: [:json], resource: p.participatable
    end
  end
end
