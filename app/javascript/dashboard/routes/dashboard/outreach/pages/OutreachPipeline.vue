<script setup>
import { ref, computed, onMounted } from 'vue';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import PhotographerEditSidebar from '../components/PhotographerEditSidebar.vue';

const COLUMNS = [
  { key: 'new', label: 'Nowy', tone: 'slate' },
  { key: 'interested', label: 'Zainteresowany', tone: 'amber' },
  { key: 'signed_up', label: 'Zarejestrowany', tone: 'indigo' },
  { key: 'first_order', label: 'Pierwsze zlecenie', tone: 'teal' },
  { key: 'active', label: 'Aktywny', tone: 'green' },
  { key: 'dormant_30d', label: 'Brak zamówień 30d+', tone: 'orange' },
  { key: 'dormant_90d', label: 'Brak zamówień 90d+', tone: 'ruby' },
  { key: 'do_not_contact', label: 'Opt-out / STOP', tone: 'slate' },
];

const TONE_CLASSES = {
  slate: 'bg-n-slate-3 text-n-slate-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  indigo: 'bg-n-brand-3 text-n-brand-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  green: 'bg-n-teal-3 text-n-teal-11',
  orange: 'bg-n-amber-3 text-n-amber-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
};

const stages = ref({});
const statsRefreshedAt = ref(null);
const loading = ref(false);
const refreshing = ref(false);
const error = ref(null);
const refreshSummary = ref(null);
const countryOptions = ref([]);
const localeOptions = ref([]);
const editingProfile = ref(null);

const fetchFacets = async () => {
  try {
    const { data } = await OutreachPhotographersAPI.facets();
    countryOptions.value = data.country_codes || [];
    localeOptions.value = data.locales || [];
  } catch (e) {
    // Non-critical — autocomplete falls back to an empty list.
  }
};

const fetchPipeline = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await OutreachPhotographersAPI.pipeline();
    stages.value = data.stages || {};
    statsRefreshedAt.value = data.stats_refreshed_at || null;
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const openEdit = profile => {
  editingProfile.value = profile;
};
const closeEdit = () => {
  editingProfile.value = null;
};
const onSaved = () => {
  // Re-fetch the pipeline so the card lands in the right column after
  // status / consent edits.
  fetchPipeline();
};

const refreshStats = async () => {
  refreshing.value = true;
  refreshSummary.value = null;
  error.value = null;
  try {
    const { data } = await OutreachPhotographersAPI.refreshStats();
    refreshSummary.value = data.result;
    await fetchPipeline();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    refreshing.value = false;
  }
};

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');
const totalInPipeline = computed(() =>
  COLUMNS.reduce((n, col) => n + (stages.value[col.key]?.length || 0), 0)
);

const daysSince = ts => {
  if (!ts) return null;
  return Math.floor((Date.now() / 1000 - ts) / 86400);
};

onMounted(() => {
  fetchPipeline();
  fetchFacets();
});
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col h-full">
    <div
      class="flex items-center justify-between gap-3 px-6 py-3 border-b border-n-weak bg-white"
    >
      <div class="flex items-center gap-3 text-xs text-n-slate-11">
        <span>
          Razem w pipeline: <strong>{{ totalInPipeline }}</strong>
        </span>
        <span v-if="statsRefreshedAt">
          Odświeżono:
          <strong>{{ formatDate(statsRefreshedAt) }}</strong>
        </span>
        <span v-else class="text-n-ruby-11">
          Statystyki zamówień nie zostały jeszcze pobrane.
        </span>
      </div>
      <button
        type="button"
        class="flex-none whitespace-nowrap h-9 px-3 text-xs font-medium text-white rounded bg-n-brand hover:opacity-90 disabled:opacity-60"
        :disabled="refreshing"
        @click="refreshStats"
      >
        {{ refreshing ? 'Odświeżanie…' : 'Odśwież statystyki zamówień' }}
      </button>
    </div>

    <div
      v-if="refreshSummary"
      class="px-6 py-2 text-xs bg-n-teal-3 text-n-teal-11"
    >
      <template v-if="refreshSummary.skipped">
        Pominięte: <strong>{{ refreshSummary.skipped }}</strong>
      </template>
      <template v-else>
        Zaktualizowane: <strong>{{ refreshSummary.updated }}</strong> · bez
        zmian: <strong>{{ refreshSummary.unchanged }}</strong> · bez
        dopasowania: <strong>{{ refreshSummary.unmatched }}</strong>
        <template v-if="refreshSummary.errors && refreshSummary.errors.length">
          · błędy: {{ refreshSummary.errors.join('; ') }}
        </template>
      </template>
    </div>

    <div v-if="error" class="px-6 py-2 text-sm bg-n-ruby-3 text-n-ruby-11">
      {{ error }}
    </div>

    <div
      v-if="loading"
      class="flex-1 flex items-center justify-center text-sm text-n-slate-11"
    >
      Ładowanie pipeline…
    </div>

    <div
      v-else
      class="flex-1 overflow-x-auto overflow-y-hidden p-4 bg-n-slate-2"
    >
      <div class="flex gap-3 h-full items-stretch min-w-max">
        <section
          v-for="col in COLUMNS"
          :key="col.key"
          class="flex flex-col w-72 flex-none bg-white border rounded-lg border-n-weak overflow-hidden"
        >
          <header
            class="flex items-center justify-between px-3 py-2 border-b border-n-weak"
          >
            <div class="flex items-center gap-2">
              <span class="text-sm font-semibold text-n-slate-12">
                {{ col.label }}
              </span>
              <span
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full"
                :class="TONE_CLASSES[col.tone]"
              >
                {{ (stages[col.key] || []).length }}
              </span>
            </div>
          </header>
          <div class="flex-1 overflow-y-auto p-2 space-y-2">
            <article
              v-for="profile in stages[col.key] || []"
              :key="profile.id"
              class="p-3 border rounded cursor-pointer transition-colors"
              :class="
                editingProfile && editingProfile.id === profile.id
                  ? 'border-n-brand bg-n-brand-3 ring-1 ring-n-brand'
                  : 'border-n-weak hover:border-n-slate-6'
              "
              @click="openEdit(profile)"
            >
              <div class="text-sm font-medium text-n-slate-12 truncate">
                {{
                  profile.business_name || profile.owner_name || profile.email
                }}
              </div>
              <div class="text-xs text-n-slate-11 truncate">
                {{ profile.email }}
              </div>
              <div
                class="flex items-center gap-2 mt-2 text-[11px] text-n-slate-11"
              >
                <span
                  class="px-1.5 py-0.5 rounded bg-n-slate-3"
                  :title="`Total orders: ${profile.orders_total}`"
                >
                  Σ {{ profile.orders_total }}
                </span>
                <span
                  class="px-1.5 py-0.5 rounded bg-n-slate-3"
                  :title="`Orders in last 30 days: ${profile.orders_last_30d}`"
                >
                  30d: {{ profile.orders_last_30d }}
                </span>
                <span
                  class="px-1.5 py-0.5 rounded bg-n-slate-3"
                  :title="`Orders in last 90 days: ${profile.orders_last_90d}`"
                >
                  90d: {{ profile.orders_last_90d }}
                </span>
              </div>
              <div
                v-if="profile.last_order_completed_at"
                class="mt-1 text-[11px] text-n-slate-11"
              >
                Ostatnie:
                {{ daysSince(profile.last_order_completed_at) }}d temu
              </div>
              <div
                v-if="profile.country_code || profile.preferred_language"
                class="mt-1 text-[11px] uppercase tracking-wide text-n-slate-10"
              >
                {{ profile.country_code || '—' }} ·
                {{ profile.preferred_language || '—' }}
              </div>
            </article>
            <div
              v-if="!(stages[col.key] || []).length"
              class="py-6 text-center text-xs text-n-slate-10 border border-dashed border-n-weak rounded"
            >
              Pusto
            </div>
          </div>
        </section>
      </div>
    </div>

    <PhotographerEditSidebar
      :profile="editingProfile"
      :country-options="countryOptions"
      :locale-options="localeOptions"
      @close="closeEdit"
      @saved="onSaved"
    />
  </div>
</template>
