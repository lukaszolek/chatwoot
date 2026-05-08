<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import ChatList from 'dashboard/components/ChatList.vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';

const store = useStore();
const route = useRoute();
const router = useRouter();

const loading = ref(false);
const error = ref('');
const inboxId = ref(0);
const queueCounts = ref({});

const QUEUES = [
  {
    key: 'action_needed',
    label: 'Do obsługi',
    description: 'Realne odpowiedzi fotografów',
    status: 'open',
    labelName: 'outreach_replied',
  },
  {
    key: 'drafts',
    label: 'Drafty',
    description: 'Wiadomości do sprawdzenia i wysłania',
    status: 'open',
    labelName: 'outreach_draft',
  },
  {
    key: 'sent',
    label: 'Wysłane / czekamy',
    description: 'Maile wysłane bez odpowiedzi',
    status: 'pending',
    labelName: 'outreach_sent',
  },
  {
    key: 'bounced',
    label: 'Bounce',
    description: 'Niedostarczone wiadomości',
    status: 'resolved',
    labelName: 'outreach_bounced',
  },
  {
    key: 'auto_reply',
    label: 'Auto-reply',
    description: 'Autorespondery i wiadomości urlopowe',
    status: 'pending',
    labelName: 'outreach_auto_reply',
  },
  {
    key: 'opt_out',
    label: 'Opt-out',
    description: 'STOP i wypisani odbiorcy',
    status: 'resolved',
    labelName: 'outreach_opt_out',
  },
  {
    key: 'errors',
    label: 'Błędy',
    description: 'Rozmowy wymagające sprawdzenia technicznego',
    status: 'open',
    labelName: 'outreach_error',
  },
];

const activeQueueKey = computed(() => route.query.queue || 'action_needed');
const activeQueue = computed(
  () => QUEUES.find(queue => queue.key === activeQueueKey.value) || QUEUES[0]
);

const fetchCounts = async () => {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await OutreachCampaignsAPI.inboxCounts();
    inboxId.value = data.inbox_id || 0;
    queueCounts.value = data.queues || {};
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const selectQueue = queue => {
  router.push({
    name: 'outreach_inbox',
    query: { queue: queue.key },
  });
};

watch(
  inboxId,
  value => {
    if (value) store.dispatch('setActiveInbox', value);
  },
  { immediate: true }
);

onMounted(fetchCounts);
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <section class="flex flex-col h-full min-h-0 bg-n-background">
    <div
      class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak"
    >
      <button
        v-for="queue in QUEUES"
        :key="queue.key"
        type="button"
        class="px-3 py-2 text-sm font-medium transition border rounded-lg"
        :class="
          activeQueue.key === queue.key
            ? 'border-n-brand bg-n-brand/10 text-n-brand'
            : 'border-n-weak bg-n-surface-1 text-n-slate-11 hover:text-n-slate-12'
        "
        :title="queue.description"
        @click="selectQueue(queue)"
      >
        <span>{{ queue.label }}</span>
        <span
          class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 ml-1 text-xs rounded-full"
          :class="
            activeQueue.key === queue.key
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{ queueCounts[queue.key] || 0 }}
        </span>
      </button>
    </div>

    <div v-if="loading" class="p-6 text-sm text-n-slate-11">
      Loading outreach inbox…
    </div>
    <div v-else-if="error" class="p-6 text-sm text-n-ruby-11">
      {{ error }}
    </div>
    <div v-else-if="!inboxId" class="p-6 text-sm text-n-slate-11">
      Photographer partnership campaign has no inbox configured.
    </div>
    <div v-else class="flex flex-1 min-h-0">
      <ChatList
        :key="`${activeQueue.key}-${inboxId}`"
        :conversation-inbox="inboxId"
        :label="activeQueue.labelName"
        :initial-status="activeQueue.status"
        @conversation-load="() => {}"
      />

      <div
        class="items-center justify-center flex-1 hidden min-w-0 border-l lg:flex border-n-weak bg-n-surface-1"
      >
        <div class="max-w-md px-8 text-center">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ activeQueue.label }}
          </h2>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ activeQueue.description }}. Wybierz rozmowę z listy, aby otworzyć
            ją w standardowym widoku Chatwoot.
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
