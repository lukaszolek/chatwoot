<script setup>
import { computed, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useVoucherCalculator,
  convertCurrency,
} from './composables/useVoucherCalculator';
import InfluencerProfilesAPI from '../../api/influencerProfiles';

const props = defineProps({
  profile: { type: Object, required: true },
});

const emit = defineEmits(['profileUpdated']);

const CURRENCIES = ['EUR', 'GBP', 'PLN'];

const { t } = useI18n();
const profileRef = toRef(props, 'profile');

const {
  CONTENT_ELEMENTS,
  includeReel,
  includeCarousel,
  includeStories,
  rightsLevel,
  contentMultiplier,
  rightsMultiplier,
  voucherValue,
} = useVoucherCalculator(profileRef);

const localMultiplier = ref(
  Number(props.profile.voucher_value_multiplier) || 1.0
);
const isSavingMultiplier = ref(false);

const selectedCurrency = ref(props.profile.voucher_currency || 'EUR');
const isSavingCurrency = ref(false);

watch(
  () => props.profile.voucher_currency,
  val => {
    if (val) selectedCurrency.value = val;
  }
);

const convertedValue = computed(() => {
  if (voucherValue.value == null) return null;
  return convertCurrency(voucherValue.value, selectedCurrency.value);
});

async function onMultiplierChange(event) {
  const value = parseFloat(event.target.value);
  localMultiplier.value = value;
  isSavingMultiplier.value = true;
  try {
    const { data } = await InfluencerProfilesAPI.updateMultiplier(
      props.profile.id,
      value
    );
    emit('profileUpdated', data.payload);
  } finally {
    isSavingMultiplier.value = false;
  }
}

async function onCurrencyChange(currency) {
  selectedCurrency.value = currency;
  isSavingCurrency.value = true;
  try {
    const { data } = await InfluencerProfilesAPI.updateCurrency(
      props.profile.id,
      currency
    );
    emit('profileUpdated', data.payload);
  } finally {
    isSavingCurrency.value = false;
  }
}

const canCalculate = computed(
  () => props.profile.fqs_score != null || props.profile.followers_count > 0
);

const toggles = computed(() => [
  {
    key: 'reel',
    label: t('INFLUENCER.VOUCHER.REEL'),
    weight: CONTENT_ELEMENTS.reel.weight,
    model: includeReel,
  },
  {
    key: 'carousel',
    label: t('INFLUENCER.VOUCHER.CAROUSEL'),
    weight: CONTENT_ELEMENTS.carousel.weight,
    model: includeCarousel,
  },
  {
    key: 'stories',
    label: t('INFLUENCER.VOUCHER.STORIES'),
    weight: CONTENT_ELEMENTS.stories.weight,
    model: includeStories,
  },
]);

function formatVoucher(value) {
  if (value == null) return '-';
  return Math.round(value).toLocaleString('pl-PL');
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
<template>
  <div class="rounded-lg border border-n-weak p-4">
    <h4 class="mb-3 text-sm font-semibold text-n-slate-12">
      {{ t('INFLUENCER.VOUCHER.TITLE') }}
    </h4>

    <template v-if="canCalculate">
      <!-- Content Package toggles -->
      <p class="mb-1.5 text-xs text-n-slate-11">
        {{ t('INFLUENCER.VOUCHER.CONTENT_PACKAGE') }}
      </p>
      <div class="mb-3 flex flex-wrap gap-1.5">
        <button
          v-for="toggle in toggles"
          :key="toggle.key"
          class="rounded-full px-3 py-1 text-xs font-medium transition-colors"
          :class="
            toggle.model.value
              ? 'bg-n-brand text-white'
              : 'bg-n-slate-3 text-n-slate-11'
          "
          @click="toggle.model.value = !toggle.model.value"
        >
          {{ toggle.label }}
          <span class="opacity-70">&times;{{ toggle.weight }}</span>
        </button>
      </div>

      <!-- Rights level -->
      <p class="mb-1.5 text-xs text-n-slate-11">
        {{ t('INFLUENCER.VOUCHER.RIGHTS') }}
      </p>
      <div
        class="mb-4 inline-flex overflow-hidden rounded-lg border border-n-weak"
      >
        <button
          class="px-3 py-1 text-xs font-medium transition-colors"
          :class="
            rightsLevel === 'standard'
              ? 'bg-n-brand text-white'
              : 'bg-n-solid-1 text-n-slate-11 hover:bg-n-background'
          "
          @click="rightsLevel = 'standard'"
        >
          {{ t('INFLUENCER.VOUCHER.STANDARD') }}
          <span class="opacity-70">1.0&times;</span>
        </button>
        <button
          class="px-3 py-1 text-xs font-medium transition-colors"
          :class="
            rightsLevel === 'extended'
              ? 'bg-n-brand text-white'
              : 'bg-n-solid-1 text-n-slate-11 hover:bg-n-background'
          "
          @click="rightsLevel = 'extended'"
        >
          {{ t('INFLUENCER.VOUCHER.EXTENDED') }}
          <span class="opacity-70">1.5&times;</span>
        </button>
      </div>

      <!-- Currency -->
      <p class="mb-1.5 text-xs text-n-slate-11">
        {{ t('INFLUENCER.VOUCHER.CURRENCY') }}
      </p>
      <div
        class="mb-4 inline-flex overflow-hidden rounded-lg border border-n-weak"
      >
        <button
          v-for="curr in CURRENCIES"
          :key="curr"
          class="px-3 py-1 text-xs font-medium transition-colors"
          :class="
            selectedCurrency === curr
              ? 'bg-n-brand text-white'
              : 'bg-n-solid-1 text-n-slate-11 hover:bg-n-background'
          "
          :disabled="isSavingCurrency"
          @click="onCurrencyChange(curr)"
        >
          {{ curr }}
        </button>
      </div>

      <!-- Multiplier slider -->
      <p class="mb-1.5 text-xs text-n-slate-11">
        {{ t('INFLUENCER.VOUCHER.MULTIPLIER_LABEL') }}
      </p>
      <div class="mb-4 flex items-center gap-3">
        <input
          type="range"
          min="0.5"
          max="2.0"
          step="0.1"
          :value="localMultiplier"
          class="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-n-slate-4 accent-n-brand"
          @change="onMultiplierChange"
          @input="localMultiplier = parseFloat($event.target.value)"
        />
        <span
          class="min-w-[3rem] text-right text-sm font-semibold text-n-slate-12"
        >
          {{ localMultiplier.toFixed(1) }}&times;
          <span v-if="isSavingMultiplier" class="text-xs text-n-slate-10">
            ...
          </span>
        </span>
      </div>

      <!-- Result -->
      <div class="rounded-lg bg-n-background p-3">
        <p class="text-xs text-n-slate-11">
          {{ t('INFLUENCER.VOUCHER.ESTIMATED_VALUE') }}
        </p>
        <p class="text-2xl font-bold text-n-slate-12">
          &asymp; {{ formatVoucher(convertedValue) }} {{ selectedCurrency }}
        </p>
        <p class="mt-1 font-mono text-[10px] text-n-slate-10">
          {{
            t('INFLUENCER.VOUCHER.FORMULA_HINT', {
              content: contentMultiplier.toFixed(1),
              rights: rightsMultiplier.toFixed(1),
              multiplier: localMultiplier.toFixed(1),
            })
          }}
        </p>
      </div>
    </template>

    <!-- Fallback for non-enriched -->
    <div v-else class="rounded-lg bg-n-blue/10 p-3">
      <p class="text-xs text-n-blue-11">
        {{ t('INFLUENCER.VOUCHER.ENRICH_HINT') }}
      </p>
    </div>
  </div>
</template>
