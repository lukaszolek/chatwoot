json.id resource.id
json.name resource.name
json.program_key resource.program_key
json.status resource.status
json.inbox_id resource.inbox_id
if resource.inbox
  json.inbox do
    json.id resource.inbox.id
    json.name resource.inbox.name
    json.channel_type resource.inbox.channel_type
  end
end
json.sender_user_id resource.sender_user_id
if resource.sender_user
  json.sender_user do
    json.id resource.sender_user.id
    json.name resource.sender_user.name
    json.email resource.sender_user.email
  end
end
json.config resource.config
json.audience_source_config resource.audience_source_config
json.manual_review_mode resource.manual_review_mode
json.participants_count resource.participants.count
json.pipeline_stages_count resource.pipeline_stages.count
json.knowledge_documents_count resource.knowledge_documents.where(active: true).count
json.learnings_count resource.learnings.where(active: true).count
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
