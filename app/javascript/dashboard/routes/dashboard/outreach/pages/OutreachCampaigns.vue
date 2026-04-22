<script setup>
import { ref, onMounted, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';

const store = useStore();

const campaigns = ref([]);
const loading = ref(false);
const savingId = ref(null);
const error = ref(null);

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const agents = computed(() => store.getters['agents/getAgents'] || []);

const emailInboxes = computed(() =>
  inboxes.value.filter(i =>
    ['Channel::Email', 'email'].includes(i.channel_type)
  )
);

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

const saveField = async (campaign, field, value) => {
  savingId.value = campaign.id;
  error.value = null;
  try {
    await OutreachCampaignsAPI.update(campaign.id, { [field]: value || null });
    await fetchAll();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    savingId.value = null;
  }
};

onMounted(async () => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  await fetchAll();
});
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
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
      <code class="px-1.5 py-0.5 text-xs rounded bg-n-slate-3">{{
        'rake outreach:blueprints:apply[1]'
      }}</code>
      to seed the photographer partnership campaign.
    </div>
    <div v-else class="flex flex-col gap-3">
      <div
        v-for="c in campaigns"
        :key="c.id"
        class="p-4 bg-white border rounded border-n-weak"
      >
        <div class="flex items-start justify-between mb-3">
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
                    : 'bg-n-slate-3 text-n-slate-11'
              "
            >
              {{ c.status }}
            </span>
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

        <div class="grid grid-cols-2 gap-4 pt-3 text-sm border-t border-n-weak">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Sending inbox</span>
            <select
              :value="c.inbox_id || ''"
              :disabled="savingId === c.id"
              class="reset-base w-full px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
              @change="saveField(c, 'inbox_id', $event.target.value)"
            >
              <option value="">— select inbox —</option>
              <option v-for="i in emailInboxes" :key="i.id" :value="i.id">
                {{ i.name }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Sender (operator)</span>
            <select
              :value="c.sender_user_id || ''"
              :disabled="savingId === c.id"
              class="reset-base w-full px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
              @change="saveField(c, 'sender_user_id', $event.target.value)"
            >
              <option value="">— select sender —</option>
              <option v-for="u in agents" :key="u.id" :value="u.id">
                {{ u.name }} ({{ u.email }})
              </option>
            </select>
          </label>
        </div>

        <p
          v-if="!c.inbox_id || !c.sender_user_id"
          class="mt-2 text-xs text-n-amber-11"
        >
          Campaign will not send mails until both an inbox and a sender are
          picked.
        </p>
      </div>
    </div>
  </div>
</template>
