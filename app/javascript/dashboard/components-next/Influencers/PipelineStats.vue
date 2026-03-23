<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

const { t } = useI18n();
const store = useStore();

const getCount = status => {
  return (
    store.getters['influencerProfiles/getKanbanColumn'](status)?.meta?.count ||
    0
  );
};

const contacted = computed(() => getCount('contacted'));
const confirmed = computed(() => getCount('confirmed'));
const contentDelivered = computed(() => getCount('content_delivered'));
const completed = computed(() => getCount('completed'));
const declined = computed(() => getCount('declined'));

const total = computed(
  () =>
    contacted.value +
    confirmed.value +
    contentDelivered.value +
    completed.value +
    declined.value
);

const pct = val => {
  if (!total.value) return 0;
  return ((val / total.value) * 100).toFixed(1);
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div
    v-if="total > 0"
    class="flex flex-wrap items-center gap-3 rounded-lg border border-n-weak bg-n-solid-1 px-4 py-2.5 text-sm"
  >
    <span class="font-medium text-n-slate-12">
      {{ t('INFLUENCER.KANBAN.PIPELINE_STATS_PENDING') }}:
      <span class="font-semibold">{{ contacted }}</span>
      <span class="text-xs text-n-slate-10">({{ pct(contacted) }}%)</span>
    </span>

    <span class="text-n-slate-10">→</span>
    <span class="text-n-amber-11">
      {{ t('INFLUENCER.KANBAN.STATUS_CONFIRMED') }}:
      <span class="font-semibold">{{ confirmed }}</span>
      <span class="text-xs text-n-slate-10">({{ pct(confirmed) }}%)</span>
    </span>

    <span class="text-n-slate-10">→</span>
    <span class="text-n-violet-11">
      {{ t('INFLUENCER.KANBAN.STATUS_CONTENT_DELIVERED') }}:
      <span class="font-semibold">{{ contentDelivered }}</span>
      <span class="text-xs text-n-slate-10">
        ({{ pct(contentDelivered) }}%)
      </span>
    </span>

    <span class="text-n-slate-10">→</span>
    <span class="text-green-700">
      {{ t('INFLUENCER.KANBAN.STATUS_COMPLETED') }}:
      <span class="font-semibold">{{ completed }}</span>
      <span class="text-xs text-n-slate-10">({{ pct(completed) }}%)</span>
    </span>

    <span class="mx-1 text-n-slate-8">|</span>
    <span class="text-n-ruby-11">
      {{ t('INFLUENCER.KANBAN.STATUS_DECLINED') }}:
      <span class="font-semibold">{{ declined }}</span>
      <span class="text-xs text-n-slate-10">({{ pct(declined) }}%)</span>
    </span>
  </div>
</template>
