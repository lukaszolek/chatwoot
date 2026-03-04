<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import InfluencerKanbanCard from './InfluencerKanbanCard.vue';

const props = defineProps({
  status: { type: String, required: true },
  label: { type: String, required: true },
  profiles: { type: Array, default: () => [] },
  count: { type: Number, default: 0 },
  hasMore: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  collapsed: { type: Boolean, default: false },
});

const emit = defineEmits([
  'select',
  'loadMore',
  'retryApify',
  'expand',
  'collapse',
]);

const { t } = useI18n();

const apifyFailedCount = computed(
  () => props.profiles.filter(p => p.apify_status === 'apify_failed').length
);
const hasCreditsError = computed(() =>
  props.profiles.some(
    p =>
      p.apify_status === 'apify_failed' &&
      p.apify_error?.includes('insufficient credits')
  )
);

const statusColors = {
  discovered: 'bg-n-blue-3 text-n-blue-11',
  enriched: 'bg-n-violet-3 text-n-violet-11',
  approved: 'bg-n-green-3 text-n-green-11',
  rejected: 'bg-n-ruby-3 text-n-ruby-11',
  contacted: 'bg-n-amber-3 text-n-amber-11',
  confirmed: 'bg-n-green-3 text-n-green-11',
};
</script>

<template>
  <!-- Collapsed state -->
  <div
    v-if="collapsed"
    class="flex flex-col items-center min-w-[48px] max-w-[48px] h-full cursor-pointer group"
    @click="emit('expand')"
  >
    <div
      class="flex flex-col items-center gap-2 px-2 py-3 rounded-lg bg-n-solid-3 hover:bg-n-solid-4 transition-colors w-full"
    >
      <span class="text-xs font-medium text-n-slate-10">
        {{ count }}
      </span>
      <span
        class="px-1.5 py-0.5 text-[10px] font-medium rounded-full whitespace-nowrap [writing-mode:vertical-rl]"
        :class="statusColors[status] || 'bg-n-solid-3'"
      >
        {{ label }}
      </span>
      <span
        class="i-lucide-chevron-right size-3 text-n-slate-10 group-hover:text-n-slate-12 transition-colors"
      />
    </div>
  </div>

  <!-- Expanded state -->
  <div v-else class="flex flex-col min-w-[280px] max-w-[320px] flex-1 h-full">
    <!-- Column header -->
    <div
      class="flex items-center justify-between px-3 py-2 mb-3 rounded-lg bg-n-solid-3"
    >
      <div class="flex items-center gap-2">
        <span
          class="px-2 py-0.5 text-xs font-medium rounded-full"
          :class="statusColors[status] || 'bg-n-solid-3'"
        >
          {{ label }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <span class="text-xs font-medium text-n-slate-10">
          {{ count }}
        </span>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 transition-colors"
          :title="t('INFLUENCER.KANBAN.COLLAPSE')"
          @click="emit('collapse')"
        >
          <span class="i-lucide-chevron-left size-3.5" />
        </button>
      </div>
    </div>

    <!-- Apify credits warning -->
    <div
      v-if="hasCreditsError"
      class="flex items-start gap-2 px-3 py-2 mb-2 text-xs rounded-lg bg-n-ruby-2 text-n-ruby-11"
    >
      <span class="i-lucide-alert-circle size-4 flex-shrink-0 mt-0.5" />
      <span>
        {{ t('INFLUENCER.KANBAN.APIFY_NO_CREDITS') }}
      </span>
    </div>

    <!-- Apify failed count warning (non-credits errors) -->
    <div
      v-else-if="apifyFailedCount > 0"
      class="flex items-center gap-2 px-3 py-2 mb-2 text-xs rounded-lg bg-n-amber-2 text-n-amber-11"
    >
      <span class="i-lucide-alert-triangle size-4 flex-shrink-0" />
      <span>
        {{
          t('INFLUENCER.KANBAN.APIFY_FAILED_COUNT', {
            count: apifyFailedCount,
          })
        }}
      </span>
    </div>

    <!-- Cards list -->
    <div class="flex flex-col gap-2 flex-1 overflow-y-auto min-h-[100px] pb-2">
      <InfluencerKanbanCard
        v-for="profile in profiles"
        :key="profile.id"
        :profile="profile"
        @select="emit('select', $event)"
        @retry-apify="emit('retryApify', $event)"
      />

      <!-- Empty state -->
      <div
        v-if="!loading && profiles.length === 0"
        class="flex items-center justify-center flex-1 text-xs text-n-slate-10 py-8"
      >
        {{ t('INFLUENCER.KANBAN.EMPTY_COLUMN') }}
      </div>

      <!-- Loading state -->
      <div
        v-if="loading"
        class="flex items-center justify-center py-4 text-xs text-n-slate-10"
      >
        <span class="i-lucide-loader-2 animate-spin size-4 mr-2" />
        {{ t('INFLUENCER.KANBAN.LOADING') }}
      </div>

      <!-- Load more -->
      <button
        v-if="hasMore && !loading && profiles.length < count"
        class="flex items-center justify-center gap-1 py-2 text-xs font-medium text-n-brand rounded-lg border border-dashed border-n-weak hover:bg-n-solid-1 transition-colors"
        @click="emit('loadMore')"
      >
        <span class="i-lucide-chevron-down size-3" />
        {{ t('INFLUENCER.KANBAN.LOAD_MORE') }}
      </button>
    </div>
  </div>
</template>
