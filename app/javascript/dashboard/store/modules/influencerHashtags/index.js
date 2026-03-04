import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  records: [],
  meta: { total: 0, page: 1, perPage: 50 },
  starredHashtags: [],
  uiFlags: {
    isFetching: false,
    isUpdating: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
