class InfluencersClub::LookalikeService
  def initialize(client: InfluencersClub::Client.new)
    @client = client
  end

  def perform(username:, platform: 'instagram', filters: {})
    body = { platform: platform, handle: username }
    body[:filters] = filters if filters.present?
    @client.post('/public/v1/lookalikes/', body)
  end
end
