/* global axios */
import ApiClient from './ApiClient';

class OutreachDraftsAPI extends ApiClient {
  constructor() {
    super('outreach/drafts', { accountScoped: true });
  }

  approvePending({
    limit = 10,
    programKey = 'photographer_partnership',
    templateSlot = 'intro',
  } = {}) {
    return axios.post(`${this.url}/approve_pending`, {
      limit,
      program_key: programKey,
      template_slot: templateSlot,
    });
  }
}

export default new OutreachDraftsAPI();
