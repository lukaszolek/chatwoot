/* global axios */
import ApiClient from './ApiClient';

class OutreachStatsAPI extends ApiClient {
  constructor() {
    super('outreach/stats', { accountScoped: true });
  }

  dailyNew(days = 14) {
    return axios.get(`${this.url}/daily_new?days=${days}`);
  }

  funnel(windowDays = 7) {
    return axios.get(`${this.url}/funnel?window_days=${windowDays}`);
  }
}

export default new OutreachStatsAPI();
