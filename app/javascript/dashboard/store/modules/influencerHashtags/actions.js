import InfluencerHashtagsAPI from '../../../api/influencerHashtags';
import types from '../../mutation-types';

export const actions = {
  async fetchHashtags({ commit }, params = {}) {
    commit(types.SET_INFLUENCER_HASHTAGS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await InfluencerHashtagsAPI.get(params);
      commit(types.SET_INFLUENCER_HASHTAGS, data);
    } finally {
      commit(types.SET_INFLUENCER_HASHTAGS_UI_FLAG, { isFetching: false });
    }
  },

  async toggleStar({ commit }, id) {
    commit(types.SET_INFLUENCER_HASHTAGS_UI_FLAG, { isUpdating: true });
    try {
      const { data } = await InfluencerHashtagsAPI.toggleStar(id);
      commit(types.UPDATE_INFLUENCER_HASHTAG, data);
      return data;
    } finally {
      commit(types.SET_INFLUENCER_HASHTAGS_UI_FLAG, { isUpdating: false });
    }
  },

  async fetchStats(_, id) {
    await InfluencerHashtagsAPI.fetchStats(id);
  },

  async bulkFetchStats(_, ids) {
    await InfluencerHashtagsAPI.bulkFetchStats(ids);
  },

  async fetchAllMissingStats(_, language) {
    const { data } = await InfluencerHashtagsAPI.fetchAllMissingStats(language);
    return data;
  },

  async fetchStarredForLanguage({ commit }, language) {
    const { data } = await InfluencerHashtagsAPI.starredForLanguage(language);
    commit(types.SET_STARRED_HASHTAGS, data);
  },
};
