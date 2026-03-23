<script setup>
import { computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import InfluencerKanbanColumn from './InfluencerKanbanColumn.vue';
import PipelineStats from './PipelineStats.vue';

const props = defineProps({
  statuses: {
    type: Array,
    default: () => [
      'discovered',
      'preselected',
      'enriched',
      'approved',
      'rejected',
    ],
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const store = useStore();

const collapsedColumns = reactive({ rejected: true });

const showPipelineStats = computed(() => props.statuses.includes('contacted'));

const statusLabels = {
  discovered: t('INFLUENCER.KANBAN.STATUS_DISCOVERED'),
  preselected: t('INFLUENCER.KANBAN.STATUS_PRESELECTED'),
  enriched: t('INFLUENCER.KANBAN.STATUS_ENRICHED'),
  approved: t('INFLUENCER.KANBAN.STATUS_APPROVED'),
  rejected: t('INFLUENCER.KANBAN.STATUS_REJECTED'),
  contacted: t('INFLUENCER.KANBAN.STATUS_CONTACTED'),
  confirmed: t('INFLUENCER.KANBAN.STATUS_CONFIRMED'),
  declined: t('INFLUENCER.KANBAN.STATUS_DECLINED'),
  content_delivered: t('INFLUENCER.KANBAN.STATUS_CONTENT_DELIVERED'),
  completed: t('INFLUENCER.KANBAN.STATUS_COMPLETED'),
};

const getColumn = status => {
  return store.getters['influencerProfiles/getKanbanColumn'](status);
};

onMounted(() => {
  store.dispatch('influencerProfiles/refreshAllKanbanColumns');
});

const loadMore = status => {
  store.dispatch('influencerProfiles/loadMoreKanban', { status });
};

const handleSelect = profile => {
  emit('select', profile);
};

const handleRetryApify = profileId => {
  store.dispatch('influencerProfiles/retryApify', { id: profileId });
};

const handleExpand = status => {
  collapsedColumns[status] = false;
  const column = getColumn(status);
  if (column.records.length === 0) {
    store.dispatch('influencerProfiles/fetchKanbanColumn', {
      status,
      page: 1,
    });
  }
};

const handleCollapse = status => {
  collapsedColumns[status] = true;
};
</script>

<template>
  <div class="flex flex-col h-full">
    <PipelineStats v-if="showPipelineStats" class="mx-4 mt-4" />
    <div class="flex gap-4 overflow-x-auto items-start flex-1 p-4">
      <InfluencerKanbanColumn
        v-for="status in statuses"
        :key="status"
        :status="status"
        :label="statusLabels[status] || status"
        :profiles="getColumn(status).records"
        :count="getColumn(status).meta.count"
        :has-more="getColumn(status).meta.hasMore"
        :loading="getColumn(status).loading"
        :collapsed="!!collapsedColumns[status]"
        @select="handleSelect"
        @load-more="loadMore(status)"
        @retry-apify="handleRetryApify"
        @expand="handleExpand(status)"
        @collapse="handleCollapse(status)"
      />
    </div>
  </div>
</template>
