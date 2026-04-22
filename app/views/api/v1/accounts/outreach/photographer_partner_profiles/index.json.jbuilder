json.meta do
  json.total @total
  json.page (params[:page] || 1).to_i
  json.per_page Api::V1::Accounts::Outreach::PhotographerPartnerProfilesController::PER_PAGE
end
json.data do
  json.array! @profiles do |profile|
    json.partial! 'api/v1/models/photographer_partner_profile', formats: [:json], resource: profile
  end
end
