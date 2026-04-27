json.stats_refreshed_at @stats_refreshed_at&.to_i
json.stages do
  @pipeline_stages.each do |stage, profiles|
    json.set! stage do
      json.array!(profiles) { |p| json.partial! 'api/v1/models/photographer_partner_profile', resource: p }
    end
  end
end
