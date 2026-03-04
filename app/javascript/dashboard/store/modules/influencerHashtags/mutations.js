import types from '../../mutation-types';

export const mutations = {
  [types.SET_INFLUENCER_HASHTAGS_UI_FLAG](state, flag) {
    state.uiFlags = { ...state.uiFlags, ...flag };
  },
  [types.SET_INFLUENCER_HASHTAGS](state, { data, meta }) {
    state.records = data;
    state.meta = meta;
  },
  [types.UPDATE_INFLUENCER_HASHTAG](state, hashtag) {
    const idx = state.records.findIndex(h => h.id === hashtag.id);
    if (idx !== -1) {
      state.records.splice(idx, 1, hashtag);
    }
  },
  [types.SET_STARRED_HASHTAGS](state, hashtags) {
    state.starredHashtags = hashtags;
  },
};
