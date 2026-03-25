class InfluencersClub::LookalikeService
  def initialize(client: InfluencersClub::Client.new)
    @client = client
  end

  def perform(username:, platform: 'instagram', filters: {})
    body = { platform: platform, filter_key: 'username', filter_value: username, paging: { limit: 10, page: 0 } }
    body[:filters] = filters if filters.present?
    @client.post('/public/v1/discovery/creators/similar/', body)
  end
end
