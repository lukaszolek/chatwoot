/* global axios */
import ApiClient from './ApiClient';

class OutreachLearningsAPI extends ApiClient {
  constructor() {
    super('outreach/campaigns', { accountScoped: true });
  }

  list(campaignId, params = {}) {
    return axios.get(`${this.url}/${campaignId}/learnings`, { params });
  }

  update(campaignId, id, payload) {
    return axios.patch(`${this.url}/${campaignId}/learnings/${id}`, {
      outbound_campaign_learning: payload,
    });
  }

  destroy(campaignId, id) {
    return axios.delete(`${this.url}/${campaignId}/learnings/${id}`);
  }
}

export default new OutreachLearningsAPI();
