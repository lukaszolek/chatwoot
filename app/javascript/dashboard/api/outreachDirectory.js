/* global axios */
import ApiClient from './ApiClient';

class OutreachDirectoryAPI extends ApiClient {
  constructor() {
    super('outreach/directory', { accountScoped: true });
  }

  search(page = 1, filters = {}) {
    const params = new URLSearchParams({ page });
    if (filters.q) params.append('q', filters.q);
    if (filters.country_code)
      params.append('country_code', filters.country_code);
    if (filters.locale) params.append('locale', filters.locale);
    return axios.get(`${this.url}/search?${params}`);
  }

  import(directoryIds) {
    return axios.post(`${this.url}/import`, { directory_ids: directoryIds });
  }
}

export default new OutreachDirectoryAPI();
