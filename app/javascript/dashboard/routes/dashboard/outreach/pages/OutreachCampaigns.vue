<script setup>
import { ref, onMounted } from 'vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';

const campaigns = ref([]);
const loading = ref(false);
const error = ref(null);

const fetchAll = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await OutreachCampaignsAPI.get();
    campaigns.value = data || [];
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const act = async (id, action) => {
  try {
    await OutreachCampaignsAPI[action](id);
    await fetchAll();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  }
};

onMounted(fetchAll);
</script>

<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<template>
  <div class="p-6">
    <div
      v-if="error"
      class="p-3 mb-4 text-sm rounded bg-n-ruby-3 text-n-ruby-11"
    >
      {{ error }}
    </div>
    <div v-if="loading" class="py-12 text-sm text-center text-n-slate-11">
      Loading…
    </div>
    <div
      v-else-if="campaigns.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No outreach campaigns yet. Run
      <code class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3">rake outreach:blueprints:apply[1]</code>
      to seed the photographer partnership campaign.
    </div>
    <div v-else class="flex flex-col gap-3">
      <div
        v-for="c in campaigns"
        :key="c.id"
        class="flex items-center justify-between p-4 bg-white border rounded border-n-weak"
      >
        <div>
          <div class="font-medium text-n-slate-12">{{ c.name }}</div>
          <div class="text-xs text-n-slate-11">
            program: <code>{{ c.program_key }}</code> ·
            {{ c.participants_count }} participants ·
            {{ c.pipeline_stages_count }} stages ·
            {{ c.templates_count }} active templates
          </div>
        </div>
        <div class="flex items-center gap-3">
          <span
            class="px-2 py-0.5 text-xs font-medium rounded-full"
            :class="
              c.status === 'active'
                ? 'bg-n-teal-3 text-n-teal-11'
                : c.status === 'paused'
                  ? 'bg-n-amber-3 text-n-amber-11'
                  : c.status === 'archived'
                    ? 'bg-n-slate-3 text-n-slate-11'
                    : 'bg-n-slate-3 text-n-slate-11'
            "
            >{{ c.status }}</span>
          <button
            v-if="c.status === 'active'"
            type="button"
            class="text-xs font-medium text-n-amber-11 hover:underline"
            @click="act(c.id, 'pause')"
          >
            Pause
          </button>
          <button
            v-else-if="c.status === 'paused' || c.status === 'draft'"
            type="button"
            class="text-xs font-medium text-n-teal-11 hover:underline"
            @click="act(c.id, 'resume')"
          >
            Resume
          </button>
          <button
            v-if="c.status !== 'archived'"
            type="button"
            class="text-xs font-medium text-n-slate-11 hover:underline"
            @click="act(c.id, 'archive')"
          >
            Archive
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
