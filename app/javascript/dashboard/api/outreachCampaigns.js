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

  retryGeneration(campaignId, participantId) {
    return axios.post(
      `${this.url}/${campaignId}/participants/${participantId}/retry_generation`
    );
  }

  markNotRelevant(campaignId, participantId) {
    return axios.post(
      `${this.url}/${campaignId}/participants/${participantId}/mark_not_relevant`
    );
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
