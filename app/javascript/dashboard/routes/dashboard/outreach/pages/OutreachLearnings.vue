<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';
import OutreachLearningsAPI from 'dashboard/api/outreachLearnings';

const SOURCE_KINDS = ['', 'operator_edit', 'operator_prompt', 'operator_note'];
const SLOTS = ['', 'intro', 'reminder', 'breakup', 'reply'];

const campaigns = ref([]);
const learnings = ref([]);
const activeCampaignId = ref(null);
const loading = ref(false);
const error = ref(null);
const savingId = ref(null);
const filters = ref({ source_kind: '', slot: '', active: '' });
const editingId = ref(null);
const editContent = ref('');

const loadCampaigns = async () => {
  const { data } = await OutreachCampaignsAPI.get();
  campaigns.value = data || [];
  if (campaigns.value.length && !activeCampaignId.value) {
    activeCampaignId.value = campaigns.value[0].id;
  }
};

const loadLearnings = async () => {
  if (!activeCampaignId.value) return;
  loading.value = true;
  try {
    const params = {};
    if (filters.value.source_kind)
      params.source_kind = filters.value.source_kind;
    if (filters.value.slot) params.slot = filters.value.slot;
    if (filters.value.active) params.active = filters.value.active;
    const { data } = await OutreachLearningsAPI.list(
      activeCampaignId.value,
      params
    );
    learnings.value = data || [];
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const refresh = async () => {
  await loadCampaigns();
  await loadLearnings();
};

const startEdit = l => {
  editingId.value = l.id;
  editContent.value = l.content;
};
const cancelEdit = () => {
  editingId.value = null;
  editContent.value = '';
};
const saveEdit = async l => {
  savingId.value = l.id;
  try {
    await OutreachLearningsAPI.update(activeCampaignId.value, l.id, {
      content: editContent.value,
    });
    cancelEdit();
    await loadLearnings();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    savingId.value = null;
  }
};
const toggleActive = async l => {
  savingId.value = l.id;
  try {
    await OutreachLearningsAPI.update(activeCampaignId.value, l.id, {
      active: !l.active,
    });
    await loadLearnings();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    savingId.value = null;
  }
};
const removeLearning = async l => {
  if (!window.confirm('Delete this learning?')) return;
  savingId.value = l.id;
  try {
    await OutreachLearningsAPI.destroy(activeCampaignId.value, l.id);
    await loadLearnings();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    savingId.value = null;
  }
};

watch(
  [
    () => filters.value.source_kind,
    () => filters.value.slot,
    () => filters.value.active,
  ],
  loadLearnings
);
watch(activeCampaignId, loadLearnings);
onMounted(refresh);

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');

const totalActive = computed(
  () => learnings.value.filter(l => l.active !== false).length
);
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

    <div
      v-if="campaigns.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No outreach campaigns yet.
    </div>

    <div v-else class="flex flex-col gap-4">
      <div class="flex items-center gap-3 flex-wrap">
        <label class="text-xs text-n-slate-11">Campaign:</label>
        <select
          v-model.number="activeCampaignId"
          class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
        >
          <option v-for="c in campaigns" :key="c.id" :value="c.id">
            {{ c.name }}
          </option>
        </select>
        <select
          v-model="filters.source_kind"
          class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
        >
          <option v-for="k in SOURCE_KINDS" :key="k" :value="k">
            {{ k || 'All sources' }}
          </option>
        </select>
        <select
          v-model="filters.slot"
          class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
        >
          <option v-for="s in SLOTS" :key="s" :value="s">
            {{ s || 'All slots' }}
          </option>
        </select>
        <label class="flex items-center gap-1 text-xs text-n-slate-11">
          <input
            type="checkbox"
            :checked="filters.active === 'true'"
            @change="filters.active = $event.target.checked ? 'true' : ''"
          />
          Active only
        </label>
        <span class="ml-auto text-xs text-n-slate-11">
          {{ learnings.length }} total · {{ totalActive }} active
        </span>
      </div>

      <div v-if="loading" class="py-12 text-sm text-center text-n-slate-11">
        Loading…
      </div>

      <div
        v-else-if="learnings.length === 0"
        class="py-12 text-sm text-center text-n-slate-11"
      >
        No learnings recorded for these filters.
      </div>

      <template v-else>
        <div
          v-for="l in learnings"
          :key="l.id"
          class="p-4 bg-white border rounded"
          :class="
            l.active === false ? 'border-n-weak opacity-60' : 'border-n-weak'
          "
        >
          <div class="flex items-start justify-between gap-3 mb-2">
            <div class="flex-1 min-w-0">
              <div
                class="flex items-center gap-2 mb-1 text-[11px] text-n-slate-11"
              >
                <span
                  class="px-1.5 py-0.5 font-mono rounded bg-n-slate-3 text-n-slate-12"
                  >{{ l.source_kind }}</span
                >
                <span
                  v-if="l.slot"
                  class="px-1.5 py-0.5 font-mono rounded bg-n-slate-3 text-n-slate-12"
                  >{{ l.slot }}</span
                >
                <span
                  v-if="l.locale"
                  class="px-1.5 py-0.5 font-mono rounded bg-n-slate-3 text-n-slate-12"
                  >{{ l.locale }}</span
                >
                <span v-if="l.user">· {{ l.user.name }}</span>
                <span>· {{ formatDate(l.created_at) }}</span>
                <span
                  v-if="l.active === false"
                  class="px-1.5 py-0.5 rounded bg-n-amber-3 text-n-amber-11"
                  >inactive</span
                >
              </div>
              <textarea
                v-if="editingId === l.id"
                v-model="editContent"
                rows="6"
                class="reset-base w-full px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
              />
              <pre
                v-else
                class="whitespace-pre-wrap text-sm text-n-slate-12 break-words"
                >{{ l.content }}</pre
              >
            </div>
            <div class="flex flex-col items-end gap-1 flex-shrink-0">
              <template v-if="editingId === l.id">
                <button
                  type="button"
                  :disabled="savingId === l.id"
                  class="text-xs font-medium text-n-brand hover:underline disabled:opacity-50"
                  @click="saveEdit(l)"
                >
                  {{ savingId === l.id ? 'Saving…' : 'Save' }}
                </button>
                <button
                  type="button"
                  class="text-xs text-n-slate-11 hover:underline"
                  @click="cancelEdit"
                >
                  Cancel
                </button>
              </template>
              <template v-else>
                <button
                  type="button"
                  class="text-xs font-medium text-n-brand hover:underline"
                  @click="startEdit(l)"
                >
                  Edit
                </button>
                <button
                  type="button"
                  :disabled="savingId === l.id"
                  class="text-xs text-n-slate-11 hover:underline"
                  @click="toggleActive(l)"
                >
                  {{ l.active === false ? 'Activate' : 'Deactivate' }}
                </button>
                <button
                  type="button"
                  :disabled="savingId === l.id"
                  class="text-xs text-n-ruby-11 hover:underline"
                  @click="removeLearning(l)"
                >
                  Delete
                </button>
              </template>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
