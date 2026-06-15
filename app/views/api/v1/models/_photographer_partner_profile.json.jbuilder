json.id resource.id
json.external_id resource.external_id

# PII — delegated to photographer-directory via PhotographerPartnerProfile#source.
# Reads return nil when the directory is unreachable (secondary DB down).
# The UI edits these through ProfileWriter so directory remains source of truth.
json.email resource.email
json.business_name resource.business_name
json.owner_name resource.owner_name
json.website resource.website
json.country_code resource.country_code
json.native_language resource.source&.native_language
json.directory_preferred_language resource.source&.preferred_language
json.preferred_language resource.preferred_language
json.instagram_handle resource.instagram_handle
json.marketing_consent resource.marketing_consent
json.source_status resource.status
json.google_rating resource.google_rating
json.google_review_count resource.google_review_count
json.directory_linked resource.source.present?

# Chatwoot-side outreach state — owned locally, editable via this controller.
json.marketing_consent_state resource.marketing_consent_state
json.partnership_status resource.partnership_status
json.partnership_status_changed_at resource.partnership_status_changed_at&.to_i
json.tags(resource.try(:tags) || [])
json.notes resource.notes
json.contact_id resource.contact_id
json.orders_total resource.orders_total
json.orders_last_30d resource.orders_last_30d
json.orders_last_90d resource.orders_last_90d
json.first_order_completed_at resource.first_order_completed_at&.to_i
json.last_order_completed_at resource.last_order_completed_at&.to_i
json.order_stats_refreshed_at resource.order_stats_refreshed_at&.to_i
json.pipeline_stage resource.pipeline_stage
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i

participant = @partnership_participants_by_profile_id&.[](resource.id)
if participant
  json.campaign_participant_id participant.id
  json.campaign_stage participant.current_stage_key
  json.campaign_paused participant.paused
  json.campaign_next_action_at participant.next_action_at&.to_i
end
