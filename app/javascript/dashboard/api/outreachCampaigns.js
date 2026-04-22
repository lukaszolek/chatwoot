/* global axios */
import ApiClient from './ApiClient';

class OutreachCampaignsAPI extends ApiClient {
  constructor() {
    super('outreach/campaigns', { accountScoped: true });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  archive(id) {
    return axios.post(`${this.url}/${id}/archive`);
  }
}

export default new OutreachCampaignsAPI();
