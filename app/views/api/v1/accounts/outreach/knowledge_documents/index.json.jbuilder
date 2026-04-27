json.array! @documents do |doc|
  json.partial! 'api/v1/models/campaign_knowledge_document', formats: [:json], resource: doc
end
