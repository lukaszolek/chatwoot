json.id resource.id
json.outbound_campaign_id resource.outbound_campaign_id
json.source_kind resource.source_kind
json.slot resource.slot
json.locale resource.locale
json.content resource.content
json.active resource.active
json.draft_message_id resource.draft_message_id
if resource.user
  json.user do
    json.id resource.user.id
    json.name resource.user.name
  end
end
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
