json.id resource.id
json.name resource.name
json.program_key resource.program_key
json.status resource.status
json.inbox_id resource.inbox_id
json.sender_user_id resource.sender_user_id
json.config resource.config
json.audience_source_config resource.audience_source_config
json.participants_count resource.participants.count
json.pipeline_stages_count resource.pipeline_stages.count
json.templates_count resource.templates.where(active: true).count
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
