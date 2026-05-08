/* global axios */
import ApiClient from './ApiClient';

class OutreachCampaignsAPI extends ApiClient {
  constructor() {
    super('outreach/campaigns', { accountScoped: true });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { outbound_campaign: payload });
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

  conversationContext(conversationDisplayId) {
    const accountId = this.accountIdFromRoute;
    return axios.get(
      `/api/v1/accounts/${accountId}/outreach/conversations/${conversationDisplayId}/context`
    );
  }

  conversationAction(conversationDisplayId, operation) {
    const accountId = this.accountIdFromRoute;
    return axios.post(
      `/api/v1/accounts/${accountId}/outreach/conversations/${conversationDisplayId}/actions/${operation}`
    );
  }

  inboxCounts() {
    const accountId = this.accountIdFromRoute;
    return axios.get(`/api/v1/accounts/${accountId}/outreach/inbox/counts`);
  }
}

export default new OutreachCampaignsAPI();
