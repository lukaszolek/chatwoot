<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import OutreachStatsAPI from 'dashboard/api/outreachStats';

const DAILY_DAYS = 14;
const WINDOW_OPTIONS = [7, 14, 30];

const COUNTRY_PALETTE = [
  'bg-n-brand',
  'bg-n-teal-9',
  'bg-n-amber-9',
  'bg-n-ruby-9',
  'bg-n-slate-9',
  'bg-n-brand-9',
  'bg-n-teal-11',
  'bg-n-amber-11',
  'bg-n-ruby-11',
  'bg-n-slate-11',
];

const dailyData = ref(null);
const funnelData = ref(null);
const loadingDaily = ref(true);
const loadingFunnel = ref(true);
const error = ref(null);
const windowDays = ref(7);

const fetchDaily = async () => {
  loadingDaily.value = true;
  error.value = null;
  try {
    const { data } = await OutreachStatsAPI.dailyNew(DAILY_DAYS);
    dailyData.value = data;
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loadingDaily.value = false;
  }
};

const fetchFunnel = async () => {
  loadingFunnel.value = true;
  error.value = null;
  try {
    const { data } = await OutreachStatsAPI.funnel(windowDays.value);
    funnelData.value = data;
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loadingFunnel.value = false;
  }
};

onMounted(() => {
  fetchDaily();
  fetchFunnel();
});

watch(windowDays, fetchFunnel);

const dayKeys = computed(() => {
  const out = [];
  const today = new Date();
  for (let i = DAILY_DAYS - 1; i >= 0; i -= 1) {
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    out.push(`${y}-${m}-${day}`);
  }
  return out;
});

const countries = computed(() => dailyData.value?.countries || []);

const countryColor = country => {
  const idx = countries.value.indexOf(country);
  return COUNTRY_PALETTE[idx % COUNTRY_PALETTE.length] || 'bg-n-slate-6';
};

const dayTotals = computed(() => {
  const buckets = dailyData.value?.buckets || {};
  return dayKeys.value.map(d => {
    const row = buckets[d] || {};
    return Object.values(row).reduce((a, b) => a + b, 0);
  });
});

const maxDay = computed(() => Math.max(1, ...dayTotals.value));

const countryTotals = computed(() => {
  const buckets = dailyData.value?.buckets || {};
  const totals = {};
  countries.value.forEach(c => {
    totals[c] = 0;
  });
  Object.values(buckets).forEach(row => {
    Object.entries(row).forEach(([c, n]) => {
      totals[c] = (totals[c] || 0) + n;
    });
  });
  return totals;
});

const grandTotal = computed(() =>
  Object.values(countryTotals.value).reduce((a, b) => a + b, 0)
);

const dayLabel = isoDay => {
  const [, m, d] = isoDay.split('-');
  return `${d}.${m}`;
};

const segmentsFor = isoDay => {
  const row = dailyData.value?.buckets?.[isoDay] || {};
  return countries.value
    .filter(c => row[c])
    .map(c => ({ country: c, count: row[c] }));
};

const prettyCountry = cc =>
  cc === '__UNKNOWN__' || cc === '__unknown__' ? '—' : cc;
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col h-full p-6 gap-6 bg-n-slate-2 overflow-y-auto">
    <div
      v-if="error"
      class="px-4 py-2 text-sm rounded bg-n-ruby-3 text-n-ruby-11"
    >
      {{ error }}
    </div>

    <!-- Daily new chart -->
    <section
      class="bg-white border rounded-lg border-n-weak overflow-hidden flex flex-col"
    >
      <header
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">
            Nowi fotografowie · ostatnie {{ DAILY_DAYS }} dni
          </h2>
          <p class="text-xs text-n-slate-11 mt-0.5">
            Podział po kraju fotografa (z directory).
          </p>
        </div>
        <div class="text-xs text-n-slate-11">
          Razem: <strong>{{ grandTotal }}</strong>
        </div>
      </header>

      <div
        v-if="loadingDaily"
        class="py-12 text-center text-sm text-n-slate-11"
      >
        Ładowanie…
      </div>

      <div
        v-else-if="grandTotal === 0"
        class="py-12 text-center text-sm text-n-slate-11"
      >
        Brak danych w wybranym oknie.
      </div>

      <div v-else class="p-4">
        <div class="flex items-end gap-1 h-56">
          <div
            v-for="(isoDay, idx) in dayKeys"
            :key="isoDay"
            class="flex-1 flex flex-col justify-end h-full group relative"
          >
            <div
              class="w-full flex flex-col-reverse rounded-t overflow-hidden border border-n-weak/40"
              :style="{ height: `${(dayTotals[idx] / maxDay) * 100}%` }"
            >
              <div
                v-for="seg in segmentsFor(isoDay)"
                :key="seg.country"
                :class="countryColor(seg.country)"
                :style="{ flexGrow: seg.count }"
                :title="`${prettyCountry(seg.country)}: ${seg.count}`"
              />
            </div>
            <div
              class="absolute -top-6 left-1/2 -translate-x-1/2 px-1.5 py-0.5 text-[10px] rounded bg-n-slate-12 text-white opacity-0 group-hover:opacity-100 pointer-events-none whitespace-nowrap"
            >
              {{ dayLabel(isoDay) }} · {{ dayTotals[idx] }}
            </div>
          </div>
        </div>
        <div class="flex justify-between mt-2 text-[10px] text-n-slate-10">
          <span
            v-for="isoDay in dayKeys"
            :key="`l-${isoDay}`"
            class="flex-1 text-center"
          >
            {{ dayLabel(isoDay) }}
          </span>
        </div>

        <div class="flex flex-wrap gap-3 mt-4 pt-3 border-t border-n-weak">
          <div
            v-for="c in countries"
            :key="c"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span class="w-3 h-3 rounded-sm" :class="countryColor(c)" />
            <span>
              {{ prettyCountry(c) }} ·
              <strong class="text-n-slate-12">{{ countryTotals[c] }}</strong>
            </span>
          </div>
        </div>
      </div>
    </section>

    <!-- Funnel -->
    <section
      class="bg-white border rounded-lg border-n-weak overflow-hidden flex flex-col"
    >
      <header
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">
            Funnel konwersji
          </h2>
          <p class="text-xs text-n-slate-11 mt-0.5">
            Kohorta: profile z pierwszą wysyłką w ostatnich
            {{ windowDays }} dniach. Statusy liczone „≥".
          </p>
        </div>
        <div class="flex items-center gap-2">
          <label for="funnel-window" class="text-xs text-n-slate-11">
            Okno:
          </label>
          <select
            id="funnel-window"
            v-model.number="windowDays"
            class="h-8 px-2 text-xs border rounded border-n-weak bg-white text-n-slate-12"
          >
            <option v-for="w in WINDOW_OPTIONS" :key="w" :value="w">
              {{ w }} dni
            </option>
          </select>
        </div>
      </header>

      <div
        v-if="loadingFunnel"
        class="py-12 text-center text-sm text-n-slate-11"
      >
        Ładowanie…
      </div>

      <div
        v-else-if="!funnelData || funnelData.cohort_size === 0"
        class="py-12 text-center text-sm text-n-slate-11"
      >
        Brak kohorty w tym oknie.
      </div>

      <div v-else class="p-4 space-y-2">
        <div class="text-xs text-n-slate-11 mb-2">
          Wielkość kohorty: <strong>{{ funnelData.cohort_size }}</strong>
        </div>
        <div
          v-for="stage in funnelData.stages"
          :key="stage.key"
          class="flex items-center gap-3"
        >
          <div class="w-32 flex-none text-sm text-n-slate-12">
            {{ stage.label }}
          </div>
          <div class="flex-1 h-7 bg-n-slate-3 rounded overflow-hidden relative">
            <div
              class="h-full bg-n-brand transition-all"
              :style="{ width: `${stage.pct}%` }"
            />
            <span
              class="absolute inset-0 flex items-center px-2 text-xs font-medium text-n-slate-12"
            >
              {{ stage.count }} ({{ stage.pct }}%)
            </span>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
