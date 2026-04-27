json.array! @learnings do |learning|
  json.partial! 'api/v1/models/outbound_campaign_learning', formats: [:json], resource: learning
end
