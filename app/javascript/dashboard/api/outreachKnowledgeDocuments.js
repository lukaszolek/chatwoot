/* global axios */
import ApiClient from './ApiClient';

class OutreachKnowledgeDocumentsAPI extends ApiClient {
  constructor() {
    super('outreach/campaigns', { accountScoped: true });
  }

  list(campaignId) {
    return axios.get(`${this.url}/${campaignId}/knowledge_documents`);
  }

  create(campaignId, payload) {
    return axios.post(`${this.url}/${campaignId}/knowledge_documents`, {
      campaign_knowledge_document: payload,
    });
  }

  update(campaignId, id, payload) {
    return axios.patch(`${this.url}/${campaignId}/knowledge_documents/${id}`, {
      campaign_knowledge_document: payload,
    });
  }

  destroy(campaignId, id) {
    return axios.delete(`${this.url}/${campaignId}/knowledge_documents/${id}`);
  }
}

export default new OutreachKnowledgeDocumentsAPI();
