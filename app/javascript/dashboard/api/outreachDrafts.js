/* global axios */
import ApiClient from './ApiClient';

class OutreachDraftsAPI extends ApiClient {
  constructor() {
    super('outreach/campaign_drafts', { accountScoped: true });
  }

  get(page = 1, filters = {}) {
    const params = new URLSearchParams({ page });
    if (filters.status) params.append('status', filters.status);
    return axios.get(`${this.url}?${params}`);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { campaign_draft: payload });
  }

  approve(id) {
    return axios.post(`${this.url}/${id}/approve`);
  }

  reject(id) {
    return axios.post(`${this.url}/${id}/reject`);
  }
}

export default new OutreachDraftsAPI();
