<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();

const tabs = [
  { key: 'inbox', label: 'Inbox', route: 'outreach_inbox' },
  {
    key: 'photographers',
    label: 'Photographers',
    route: 'outreach_photographers',
  },
  { key: 'pipeline', label: 'Pipeline', route: 'outreach_pipeline' },
  { key: 'stats', label: 'Statystyki', route: 'outreach_stats' },
  { key: 'campaigns', label: 'Campaigns', route: 'outreach_campaigns' },
  { key: 'knowledge', label: 'Knowledge', route: 'outreach_knowledge' },
  { key: 'learnings', label: 'Learnings', route: 'outreach_learnings' },
];

const activeKey = computed(() => {
  if (route.name === 'outreach_inbox') return 'inbox';
  if (route.name === 'outreach_pipeline') return 'pipeline';
  if (route.name === 'outreach_stats') return 'stats';
  if (route.name === 'outreach_campaigns') return 'campaigns';
  if (route.name === 'outreach_knowledge') return 'knowledge';
  if (route.name === 'outreach_learnings') return 'learnings';
  return 'photographers';
});
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12">Outreach</h1>
        <p class="text-sm text-n-slate-11">
          Photographer partnership outbound campaigns
        </p>
      </div>
    </header>

    <nav
      class="flex items-center gap-1 px-6 border-b border-n-weak flex-shrink-0"
    >
      <router-link
        v-for="tab in tabs"
        :key="tab.key"
        :to="{ name: tab.route }"
        class="px-4 py-3 text-sm font-medium transition border-b-2"
        :class="
          activeKey === tab.key
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
      >
        {{ tab.label }}
      </router-link>
    </nav>

    <main class="flex-1 overflow-auto">
      <router-view />
    </main>
  </div>
</template>
