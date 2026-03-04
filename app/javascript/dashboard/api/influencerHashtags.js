/* global axios */
import ApiClient from './ApiClient';

class InfluencerHashtagsAPI extends ApiClient {
  constructor() {
    super('influencer_hashtags', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  toggleStar(id) {
    return axios.patch(`${this.url}/${id}/toggle_star`);
  }

  fetchStats(id) {
    return axios.post(`${this.url}/${id}/fetch_stats`);
  }

  bulkFetchStats(ids) {
    return axios.post(`${this.url}/bulk_fetch_stats`, { ids });
  }

  fetchAllMissingStats(language) {
    const params = {};
    if (language) params.language = language;
    return axios.post(`${this.url}/fetch_all_missing_stats`, params);
  }

  starredForLanguage(language) {
    return axios.get(`${this.url}/starred_for_language`, {
      params: { language },
    });
  }
}

export default new InfluencerHashtagsAPI();
