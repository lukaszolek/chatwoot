<script setup>
import { ref, reactive, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import InfluencerCreditsBadge from './InfluencerCreditsBadge.vue';
import InfluencerSearchHistory from './InfluencerSearchHistory.vue';

const store = useStore();
const { t } = useI18n();
const uiFlags = useMapGetter('influencerProfiles/getUIFlags');
const starredHashtags = useMapGetter('influencerHashtags/getStarredHashtags');
const lastSearchParams = useMapGetter('influencerProfiles/getLastSearchParams');
const searchError = ref('');

const EU_COUNTRIES = [
  { code: 'DE', name: 'Germany' },
  { code: 'PL', name: 'Poland' },
  { code: 'FR', name: 'France' },
  { code: 'NL', name: 'Netherlands' },
  { code: 'GB', name: 'United Kingdom' },
  { code: 'IT', name: 'Italy' },
  { code: 'ES', name: 'Spain' },
  { code: 'AT', name: 'Austria' },
  { code: 'BE', name: 'Belgium' },
  { code: 'DK', name: 'Denmark' },
  { code: 'SE', name: 'Sweden' },
];

const LANGUAGES = [
  { code: '', label: 'Any' },
  { code: 'en', label: 'English' },
  { code: 'de', label: 'Deutsch' },
  { code: 'pl', label: 'Polski' },
  { code: 'fr', label: 'Français' },
  { code: 'nl', label: 'Nederlands' },
  { code: 'it', label: 'Italiano' },
  { code: 'es', label: 'Español' },
  { code: 'da', label: 'Dansk' },
  { code: 'sv', label: 'Svenska' },
];

const DEFAULT_FILTERS = {
  ai_search: '',
  followers_min: 5000,
  followers_max: 30000,
  location: [],
  engagement_percent_min: '',
  engagement_percent_max: 15,
  gender: '',
  profile_language: '',
  hashtags: '',
  keywords_in_bio: '',
  last_post_days: 30,
};

const COUNTRY_TO_LANGUAGE = {
  DE: 'de',
  AT: 'de',
  CH: 'de',
  PL: 'pl',
  FR: 'fr',
  BE: 'fr',
  NL: 'nl',
  GB: 'en',
  US: 'en',
  IT: 'it',
  ES: 'es',
  DK: 'da',
  SE: 'sv',
};

const filters = reactive({ ...DEFAULT_FILTERS });

const selectedLanguages = computed(() => {
  const langs = new Set();
  filters.location.forEach(code => {
    const lang = COUNTRY_TO_LANGUAGE[code];
    if (lang) langs.add(lang);
  });
  return [...langs];
});

watch(selectedLanguages, langs => {
  if (langs.length === 1) {
    store.dispatch('influencerHashtags/fetchStarredForLanguage', langs[0]);
  }
});

function buildPayload() {
  const payload = {
    ai_search: filters.ai_search || undefined,
    followers: { min: filters.followers_min, max: filters.followers_max },
    location: filters.location.length ? [...filters.location] : undefined,
  };

  if (filters.engagement_percent_min)
    payload.engagement_percent_min = filters.engagement_percent_min;
  if (filters.engagement_percent_max)
    payload.engagement_percent_max = filters.engagement_percent_max;
  if (filters.gender) payload.gender = filters.gender.toLowerCase();
  if (filters.profile_language)
    payload.profile_language = [filters.profile_language];
  if (filters.hashtags)
    payload.hashtags = filters.hashtags
      .split(/[,\s]+/)
      .map(h => h.trim())
      .filter(Boolean);
  if (filters.keywords_in_bio)
    payload.keywords_in_bio = filters.keywords_in_bio
      .split(',')
      .map(k => k.trim())
      .filter(Boolean);
  if (filters.last_post_days)
    payload.last_post_days = filters.last_post_days;

  return payload;
}

async function handleSearch() {
  const payload = buildPayload();

  // If same filters as last search, fetch next page instead of page 1
  const isSameSearch =
    lastSearchParams.value &&
    JSON.stringify(payload) === JSON.stringify(lastSearchParams.value);
  const page = isSameSearch ? 'next' : 1;

  searchError.value = '';
  try {
    await store.dispatch('influencerProfiles/search', {
      filters: payload,
      page,
    });
  } catch (error) {
    const message =
      error?.response?.data?.error || t('INFLUENCER.SEARCH.API_ERROR');
    searchError.value = message;
    useAlert(message);
  }
}

function applyHistorySearch(queryParams) {
  Object.assign(filters, { ...DEFAULT_FILTERS });
  if (queryParams.ai_search) filters.ai_search = queryParams.ai_search;
  if (queryParams.followers?.min)
    filters.followers_min = queryParams.followers.min;
  if (queryParams.followers?.max)
    filters.followers_max = queryParams.followers.max;
  if (queryParams.location) filters.location = [...queryParams.location];
  if (queryParams.engagement_percent_min)
    filters.engagement_percent_min = queryParams.engagement_percent_min;
  if (queryParams.engagement_percent_max)
    filters.engagement_percent_max = queryParams.engagement_percent_max;
  if (queryParams.gender) filters.gender = queryParams.gender;
  if (queryParams.profile_language)
    filters.profile_language = Array.isArray(queryParams.profile_language)
      ? queryParams.profile_language[0]
      : queryParams.profile_language;
  if (queryParams.hashtags)
    filters.hashtags = Array.isArray(queryParams.hashtags)
      ? queryParams.hashtags.join(', ')
      : queryParams.hashtags;
  if (queryParams.keywords_in_bio)
    filters.keywords_in_bio = Array.isArray(queryParams.keywords_in_bio)
      ? queryParams.keywords_in_bio.join(', ')
      : queryParams.keywords_in_bio;
  if (queryParams.last_post_days)
    filters.last_post_days = queryParams.last_post_days;

  handleSearch();
}

function toggleHashtagChip(tag) {
  const current = filters.hashtags
    .split(',')
    .map(h => h.trim())
    .filter(Boolean);
  const idx = current.indexOf(tag);
  if (idx >= 0) {
    current.splice(idx, 1);
  } else {
    current.push(tag);
  }
  filters.hashtags = current.join(', ');
}

function toggleCountry(code) {
  const idx = filters.location.indexOf(code);
  if (idx >= 0) {
    filters.location.splice(idx, 1);
  } else {
    filters.location.push(code);
  }
}
</script>

<template>
  <div class="border-b border-n-weak p-4">
    <!-- Row 1: Quick filters -->
    <div class="flex flex-wrap items-end gap-4">
      <div class="flex-1">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.AI_SEARCH') }}
        </label>
        <input
          v-model="filters.ai_search"
          type="text"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
          :placeholder="t('INFLUENCER.SEARCH.AI_SEARCH_PLACEHOLDER')"
        />
      </div>

      <div class="w-28">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.FOLLOWERS_MIN') }}
        </label>
        <input
          v-model.number="filters.followers_min"
          type="number"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
        />
      </div>

      <div class="w-28">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.FOLLOWERS_MAX') }}
        </label>
        <input
          v-model.number="filters.followers_max"
          type="number"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
        />
      </div>

      <button
        class="rounded-lg bg-n-brand px-4 py-1.5 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
        :disabled="uiFlags.isSearching"
        @click="handleSearch"
      >
        {{
          uiFlags.isSearching
            ? t('INFLUENCER.SEARCH.SEARCHING')
            : t('INFLUENCER.SEARCH.BUTTON')
        }}
      </button>
    </div>

    <div
      v-if="searchError"
      class="mt-2 rounded-lg bg-n-ruby/10 px-3 py-2 text-xs text-red-700"
    >
      {{ searchError }}
    </div>

    <!-- Row 2: Country toggles -->
    <div class="mt-3 flex flex-wrap gap-1.5">
      <button
        v-for="country in EU_COUNTRIES"
        :key="country.code"
        class="rounded-md px-2 py-0.5 text-xs font-medium transition-colors"
        :class="
          filters.location.includes(country.code)
            ? 'bg-n-brand text-white'
            : 'bg-n-background text-n-slate-11 hover:bg-n-weak'
        "
        @click="toggleCountry(country.code)"
      >
        {{ country.code }}
      </button>
    </div>

    <!-- Starred hashtag chips -->
    <div
      v-if="selectedLanguages.length === 1 && starredHashtags.length"
      class="mt-2 flex flex-wrap gap-1.5"
    >
      <button
        v-for="h in starredHashtags"
        :key="h.id"
        class="rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors"
        :class="
          filters.hashtags
            .split(',')
            .map(s => s.trim())
            .includes(h.tag)
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-weak'
        "
        @click="toggleHashtagChip(h.tag)"
      >
        #{{ h.tag }}
      </button>
    </div>

    <!-- Advanced filters (always visible) -->
    <div class="mt-3 flex flex-wrap items-end gap-4">
      <div class="w-24">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.MIN_ER') }}
        </label>
        <input
          v-model.number="filters.engagement_percent_min"
          type="number"
          step="0.1"
          min="0"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
          :placeholder="t('INFLUENCER.SEARCH.MIN_ER_PLACEHOLDER')"
        />
      </div>

      <div class="w-24">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.MAX_ER') }}
        </label>
        <input
          v-model.number="filters.engagement_percent_max"
          type="number"
          step="0.1"
          min="0"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
          :placeholder="t('INFLUENCER.SEARCH.MAX_ER_PLACEHOLDER')"
        />
      </div>

      <div class="w-28">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.GENDER') }}
        </label>
        <select
          v-model="filters.gender"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
        >
          <option value="">
            {{ t('INFLUENCER.SEARCH.GENDER_ANY') }}
          </option>
          <option value="male">
            {{ t('INFLUENCER.SEARCH.GENDER_MALE') }}
          </option>
          <option value="female">
            {{ t('INFLUENCER.SEARCH.GENDER_FEMALE') }}
          </option>
        </select>
      </div>

      <div class="w-36">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.LANGUAGE') }}
        </label>
        <select
          v-model="filters.profile_language"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
        >
          <option v-for="lang in LANGUAGES" :key="lang.code" :value="lang.code">
            {{ lang.label }}
          </option>
        </select>
      </div>

      <div class="flex-1 min-w-[200px]">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.HASHTAGS') }}
        </label>
        <input
          v-model="filters.hashtags"
          type="text"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
          :placeholder="t('INFLUENCER.SEARCH.HASHTAGS_PLACEHOLDER')"
        />
      </div>

      <div class="flex-1 min-w-[200px]">
        <label class="mb-1 block text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.KEYWORDS_IN_BIO') }}
        </label>
        <input
          v-model="filters.keywords_in_bio"
          type="text"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm"
          :placeholder="t('INFLUENCER.SEARCH.KEYWORDS_IN_BIO_PLACEHOLDER')"
        />
      </div>

      <label
        class="flex cursor-pointer items-center gap-2 self-end rounded-lg px-2 py-1.5"
      >
        <input
          type="checkbox"
          :checked="!!filters.last_post_days"
          class="size-3.5 rounded accent-n-brand"
          @change="filters.last_post_days = $event.target.checked ? 30 : 0"
        />
        <span class="whitespace-nowrap text-xs font-medium text-n-slate-11">
          {{ t('INFLUENCER.SEARCH.ACTIVE_LAST_30_DAYS') }}
        </span>
      </label>
    </div>

    <!-- Credits badge -->
    <div class="mt-3">
      <InfluencerCreditsBadge />
    </div>

    <!-- Search history -->
    <InfluencerSearchHistory @select="applyHistorySearch" />
  </div>
</template>
