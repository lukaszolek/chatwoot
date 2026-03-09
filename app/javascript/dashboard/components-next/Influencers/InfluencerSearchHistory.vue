<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const emit = defineEmits(['select']);
const store = useStore();
const { t } = useI18n();

const collapsed = ref(true);
const searchHistory = useMapGetter('influencerProfiles/getSearchHistory');

const hasHistory = computed(() => searchHistory.value.length > 0);

onMounted(() => {
  store.dispatch('influencerProfiles/fetchSearchHistory');
});

const COUNTRY_NAMES = {
  DE: 'Germany',
  PL: 'Poland',
  FR: 'France',
  NL: 'Netherlands',
  GB: 'UK',
  IT: 'Italy',
  ES: 'Spain',
  AT: 'Austria',
  BE: 'Belgium',
  DK: 'Denmark',
  SE: 'Sweden',
};

function formatK(n) {
  if (!n) return '0';
  return n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
}

function summarize(item) {
  const params = item.query_params || {};
  const parts = [];

  if (params.ai_search) parts.push(`"${params.ai_search}"`);

  const locations = Array.isArray(params.location) ? params.location : [];
  if (locations.length)
    parts.push(locations.map(c => COUNTRY_NAMES[c] || c).join(', '));

  const min = params.followers?.min;
  const max = params.followers?.max;
  if (min || max) parts.push(`${formatK(min)}-${formatK(max)}`);

  if (params.profile_language) {
    const langs = Array.isArray(params.profile_language)
      ? params.profile_language
      : [params.profile_language];
    parts.push(langs.join(', '));
  }

  if (params.hashtags) {
    const tags = Array.isArray(params.hashtags)
      ? params.hashtags
      : [params.hashtags];
    if (tags.length) parts.push(`#${tags.slice(0, 3).join(' #')}`);
  }

  return parts.join(' / ') || t('INFLUENCER.HISTORY.EMPTY');
}

function formatDate(dateStr) {
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
</script>

<template>
  <div v-if="hasHistory" class="mt-3">
    <button
      class="flex items-center gap-1 text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
      @click="collapsed = !collapsed"
    >
      <!-- eslint-disable vue/no-bare-strings-in-template -->
      <span
        class="inline-block transition-transform"
        :class="collapsed ? '' : 'rotate-90'"
      >
        &#9656;
      </span>
      <!-- eslint-enable vue/no-bare-strings-in-template -->
      {{ t('INFLUENCER.HISTORY.TITLE') }}
      <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
      <span class="text-n-slate-10">({{ searchHistory.length }})</span>
    </button>

    <div v-if="!collapsed" class="mt-2 max-h-48 space-y-1 overflow-y-auto">
      <button
        v-for="item in searchHistory"
        :key="item.id"
        class="flex w-full items-center justify-between rounded-lg px-3 py-1.5 text-left text-xs hover:bg-n-weak"
        @click="emit('select', item.query_params)"
      >
        <span class="flex-1 truncate text-n-slate-12">
          {{ summarize(item) }}
        </span>
        <span class="ml-3 flex shrink-0 items-center gap-2 text-n-slate-10">
          <span>
            {{
              t('INFLUENCER.HISTORY.RESULTS_COUNT', {
                count: item.results_count || 0,
              })
            }}
          </span>
          <span>
            {{
              t('INFLUENCER.HISTORY.PAGES_FETCHED', {
                count: item.pages_fetched || 0,
              })
            }}
          </span>
          <span>{{ formatDate(item.updated_at) }}</span>
        </span>
      </button>
    </div>
  </div>
</template>
