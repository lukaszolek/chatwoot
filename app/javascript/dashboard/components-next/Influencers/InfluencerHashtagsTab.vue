<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';

const store = useStore();
const { t } = useI18n();

const uiFlags = useMapGetter('influencerHashtags/getUIFlags');
const hashtags = useMapGetter('influencerHashtags/getHashtags');
const meta = useMapGetter('influencerHashtags/getMeta');

const languageFilter = ref('');
const minPostsFilter = ref('');
const missingStatsFilter = ref(false);
const starredFilter = ref(false);
const sortColumn = ref('');
const sortDirection = ref('desc');
const selectedIds = ref([]);

const LANGUAGES = [
  { value: '', label: 'All' },
  { value: 'en', label: 'English' },
  { value: 'de', label: 'Deutsch' },
  { value: 'pl', label: 'Polski' },
  { value: 'fr', label: 'Français' },
  { value: 'nl', label: 'Nederlands' },
  { value: 'it', label: 'Italiano' },
  { value: 'es', label: 'Español' },
  { value: 'da', label: 'Dansk' },
  { value: 'sv', label: 'Svenska' },
];

const MIN_POSTS_OPTIONS = [
  { value: '', label: 'Any posts' },
  { value: '1000', label: '1k+' },
  { value: '10000', label: '10k+' },
  { value: '100000', label: '100k+' },
  { value: '1000000', label: '1M+' },
];

const missingStatsCount = computed(() => meta.value?.missing_stats_count ?? 0);

const allSelected = computed({
  get: () =>
    hashtags.value.length > 0 &&
    selectedIds.value.length === hashtags.value.length,
  set: val => {
    selectedIds.value = val ? hashtags.value.map(h => h.id) : [];
  },
});

function buildParams(page = 1) {
  const params = {
    page,
    sort: sortColumn.value,
    direction: sortDirection.value,
  };
  if (languageFilter.value) params.language = languageFilter.value;
  if (minPostsFilter.value) params.min_posts = minPostsFilter.value;
  if (missingStatsFilter.value) params.missing_stats = 'true';
  if (starredFilter.value) params.starred = 'true';
  return params;
}

function fetchHashtags(page = 1) {
  store.dispatch('influencerHashtags/fetchHashtags', buildParams(page));
  selectedIds.value = [];
}

watch(languageFilter, () => fetchHashtags(1));
watch(minPostsFilter, () => fetchHashtags(1));

function handleSort(col) {
  if (sortColumn.value === col) {
    sortDirection.value = sortDirection.value === 'desc' ? 'asc' : 'desc';
  } else {
    sortColumn.value = col;
    sortDirection.value = 'desc';
  }
  fetchHashtags(1);
}

function sortIcon(col) {
  if (sortColumn.value !== col) return '';
  return sortDirection.value === 'asc' ? ' ↑' : ' ↓';
}

async function toggleStar(id) {
  await store.dispatch('influencerHashtags/toggleStar', id);
}

async function fetchStats(id) {
  await store.dispatch('influencerHashtags/fetchStats', id);
  useAlert(t('INFLUENCER.HASHTAGS.STATS_QUEUED'));
}

async function bulkFetchStats() {
  if (!selectedIds.value.length) return;
  await store.dispatch('influencerHashtags/bulkFetchStats', selectedIds.value);
  useAlert(
    t('INFLUENCER.HASHTAGS.BULK_STATS_QUEUED', {
      count: selectedIds.value.length,
    })
  );
  selectedIds.value = [];
}

async function fetchAllMissing() {
  const result = await store.dispatch(
    'influencerHashtags/fetchAllMissingStats',
    languageFilter.value || undefined
  );
  useAlert(
    t('INFLUENCER.HASHTAGS.BULK_STATS_QUEUED', {
      count: result?.count ?? 0,
    })
  );
}

function toggleSelect(id) {
  const idx = selectedIds.value.indexOf(id);
  if (idx >= 0) {
    selectedIds.value.splice(idx, 1);
  } else {
    selectedIds.value.push(id);
  }
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString();
}

function formatNumber(n) {
  if (n == null) return '—';
  return n.toLocaleString();
}

onMounted(() => fetchHashtags());
</script>

<template>
  <div class="p-4">
    <!-- Filters row -->
    <div class="mb-4 flex flex-wrap items-center gap-3">
      <Select v-model="languageFilter" :options="LANGUAGES" />
      <Select v-model="minPostsFilter" :options="MIN_POSTS_OPTIONS" />

      <label
        class="flex cursor-pointer items-center gap-1.5 text-sm text-n-slate-11"
      >
        <input
          v-model="missingStatsFilter"
          type="checkbox"
          class="rounded"
          @change="fetchHashtags(1)"
        />
        {{ t('INFLUENCER.HASHTAGS.MISSING_STATS_ONLY') }}
      </label>

      <label
        class="flex cursor-pointer items-center gap-1.5 text-sm text-n-slate-11"
      >
        <input
          v-model="starredFilter"
          type="checkbox"
          class="rounded"
          @change="fetchHashtags(1)"
        />
        {{ t('INFLUENCER.HASHTAGS.STARRED_ONLY') }}
      </label>

      <div class="ml-auto flex items-center gap-2">
        <button
          v-if="selectedIds.length"
          class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white hover:opacity-90"
          @click="bulkFetchStats"
        >
          {{ t('INFLUENCER.HASHTAGS.FETCH_STATS') }} ({{ selectedIds.length }})
        </button>
        <button
          v-if="missingStatsCount > 0"
          class="rounded-lg border border-n-weak px-3 py-1.5 text-sm font-medium text-n-slate-12 hover:bg-n-background"
          @click="fetchAllMissing"
        >
          {{
            t('INFLUENCER.HASHTAGS.FETCH_ALL_MISSING', {
              count: missingStatsCount,
            })
          }}
        </button>
      </div>

      <div v-if="uiFlags.isFetching" class="text-sm text-n-slate-11">
        {{ t('INFLUENCER.HASHTAGS.LOADING') }}
      </div>
    </div>

    <!-- Table -->
    <div class="overflow-x-auto rounded-lg border border-n-weak">
      <table class="w-full text-sm">
        <thead>
          <tr
            class="border-b border-n-weak bg-n-background text-left text-xs font-medium text-n-slate-11"
          >
            <th class="w-8 px-3 py-2">
              <input v-model="allSelected" type="checkbox" class="rounded" />
            </th>
            <th class="w-8 px-3 py-2">
              {{ t('INFLUENCER.HASHTAGS.STAR') }}
            </th>
            <th class="cursor-pointer px-3 py-2" @click="handleSort('tag')">
              {{ t('INFLUENCER.HASHTAGS.TAG') }}{{ sortIcon('tag') }}
            </th>
            <th class="w-24 px-3 py-2">
              {{ t('INFLUENCER.HASHTAGS.LANGUAGE') }}
            </th>
            <th
              class="w-28 cursor-pointer px-3 py-2 text-right"
              @click="handleSort('profiles_count')"
            >
              {{ t('INFLUENCER.HASHTAGS.PROFILES')
              }}{{ sortIcon('profiles_count') }}
            </th>
            <th
              class="w-28 cursor-pointer px-3 py-2 text-right"
              @click="handleSort('posts_count')"
            >
              {{ t('INFLUENCER.HASHTAGS.POSTS') }}{{ sortIcon('posts_count') }}
            </th>
            <th
              class="w-28 cursor-pointer px-3 py-2"
              @click="handleSort('stats_fetched_at')"
            >
              {{ t('INFLUENCER.HASHTAGS.STATS_DATE')
              }}{{ sortIcon('stats_fetched_at') }}
            </th>
            <th class="w-24 px-3 py-2">
              {{ t('INFLUENCER.HASHTAGS.ACTIONS_HEADER') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="hashtag in hashtags"
            :key="hashtag.id"
            class="border-b border-n-weak last:border-b-0 hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2">
              <input
                type="checkbox"
                class="rounded"
                :checked="selectedIds.includes(hashtag.id)"
                @change="toggleSelect(hashtag.id)"
              />
            </td>
            <td class="px-3 py-2">
              <button
                class="text-lg leading-none"
                :class="
                  hashtag.starred
                    ? 'text-yellow-500'
                    : 'text-n-slate-8 hover:text-yellow-400'
                "
                @click="toggleStar(hashtag.id)"
              >
                {{ hashtag.starred ? '★' : '☆' }}
              </button>
            </td>
            <td class="px-3 py-2 font-medium">#{{ hashtag.tag }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ hashtag.language }}
            </td>
            <td class="px-3 py-2 text-right tabular-nums">
              {{ formatNumber(hashtag.profiles_count) }}
            </td>
            <td class="px-3 py-2 text-right tabular-nums">
              {{ formatNumber(hashtag.posts_count) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ formatDate(hashtag.stats_fetched_at) }}
            </td>
            <td class="px-3 py-2">
              <button
                class="rounded bg-n-background px-2 py-1 text-xs font-medium text-n-slate-11 hover:bg-n-weak"
                @click="fetchStats(hashtag.id)"
              >
                {{ t('INFLUENCER.HASHTAGS.FETCH_STATS') }}
              </button>
            </td>
          </tr>
          <tr v-if="!hashtags.length && !uiFlags.isFetching">
            <td colspan="8" class="px-3 py-8 text-center text-n-slate-11">
              {{ t('INFLUENCER.HASHTAGS.EMPTY') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Pagination -->
    <div
      v-if="meta.total > meta.per_page"
      class="mt-4 flex items-center justify-between text-sm text-n-slate-11"
    >
      <span>
        {{
          t('INFLUENCER.HASHTAGS.SHOWING', {
            from: (meta.page - 1) * meta.per_page + 1,
            to: Math.min(meta.page * meta.per_page, meta.total),
            total: meta.total,
          })
        }}
      </span>
      <div class="flex gap-2">
        <button
          :disabled="meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-1 hover:bg-n-background disabled:opacity-50"
          @click="fetchHashtags(meta.page - 1)"
        >
          <span class="i-lucide-chevron-left size-4" />
        </button>
        <button
          :disabled="meta.page * meta.per_page >= meta.total"
          class="rounded-lg border border-n-weak px-3 py-1 hover:bg-n-background disabled:opacity-50"
          @click="fetchHashtags(meta.page + 1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
