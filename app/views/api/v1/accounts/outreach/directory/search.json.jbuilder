json.meta do
  json.total @total
  json.page (params[:page] || 1).to_i
  json.per_page Api::V1::Accounts::Outreach::DirectoryController::PER_PAGE
end
json.data do
  json.array! @results do |row|
    json.id row.id
    json.email row.email
    json.business_name row.business_name
    json.owner_name row.owner_name
    json.website row.website
    json.country_code row.country_code&.upcase
    json.preferred_language row.preferred_language
    json.instagram_handle row.instagram_handle
    json.marketing_consent row.marketing_consent
    json.email_validation_status row.email_validation_status
    json.already_enrolled @enrolled_ids.include?(row.id.to_s)
    json.in_directory_campaign @in_directory_campaign_ids.include?(row.id)
  end
end
