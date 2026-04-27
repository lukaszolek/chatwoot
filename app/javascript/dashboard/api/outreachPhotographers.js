/* global axios */
import ApiClient from './ApiClient';

class OutreachPhotographersAPI extends ApiClient {
  constructor() {
    super('outreach/photographer_partner_profiles', { accountScoped: true });
  }

  get(page = 1, filters = {}) {
    const params = new URLSearchParams({ page });
    if (filters.status) params.append('status', filters.status);
    if (filters.country_code)
      params.append('country_code', filters.country_code);
    if (filters.locale) params.append('locale', filters.locale);
    if (filters.q) params.append('q', filters.q);
    return axios.get(`${this.url}?${params}`);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, {
      photographer_partner_profile: payload,
    });
  }

  optOut(id, reason = 'operator_manual') {
    return axios.post(`${this.url}/${id}/opt_out`, { reason });
  }

  create(payload, enroll = true) {
    return axios.post(this.url, {
      photographer_partner_profile: payload,
      enroll,
    });
  }

  enroll(id) {
    return axios.post(`${this.url}/${id}/enroll`);
  }

  facets() {
    return axios.get(`${this.url}/facets`);
  }

  pipeline() {
    return axios.get(`${this.url}/pipeline`);
  }

  refreshStats() {
    return axios.post(`${this.url}/refresh_stats`);
  }
}

export default new OutreachPhotographersAPI();
