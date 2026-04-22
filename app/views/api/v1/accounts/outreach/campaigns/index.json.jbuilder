json.array! @campaigns do |campaign|
  json.partial! 'api/v1/models/outbound_campaign', formats: [:json], resource: campaign
end
