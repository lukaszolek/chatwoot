<script setup>
import { computed, onMounted, ref } from 'vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';
import OutreachKnowledgeAPI from 'dashboard/api/outreachKnowledgeDocuments';

const KINDS = [
  'goal',
  'product',
  'program_rules',
  'faq',
  'tone',
  'copywriting',
  'intro_seed',
  'reply_signup',
  'open_issues',
  'custom',
];

const KNOWN_LOCALES = [
  'pl',
  'en',
  'de',
  'fr',
  'it',
  'es',
  'nl',
  'cs',
  'sk',
  'ro',
  'hr',
  'da',
  'fi',
  'sv',
  'hu',
  'el',
];

const campaigns = ref([]);
const documentsByCampaign = ref({});
const activeCampaignId = ref(null);
const loading = ref(false);
const error = ref(null);
const savingId = ref(null);
const editing = ref(null);
const editForm = ref({});

const activeDocuments = computed(
  () => documentsByCampaign.value[activeCampaignId.value] || []
);

const groupedDocs = computed(() => {
  const groups = {};
  activeDocuments.value.forEach(d => {
    const key = d.kind || 'custom';
    groups[key] ||= [];
    groups[key].push(d);
  });
  Object.values(groups).forEach(list =>
    list.sort((a, b) => (a.position || 0) - (b.position || 0))
  );
  return groups;
});

const loadCampaigns = async () => {
  const { data } = await OutreachCampaignsAPI.get();
  campaigns.value = data || [];
  if (campaigns.value.length && !activeCampaignId.value) {
    activeCampaignId.value = campaigns.value[0].id;
  }
};

const loadDocuments = async campaignId => {
  if (!campaignId) return;
  const { data } = await OutreachKnowledgeAPI.list(campaignId);
  documentsByCampaign.value = {
    ...documentsByCampaign.value,
    [campaignId]: data || [],
  };
};

const refresh = async () => {
  loading.value = true;
  error.value = null;
  try {
    await loadCampaigns();
    if (activeCampaignId.value) await loadDocuments(activeCampaignId.value);
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const selectCampaign = async id => {
  activeCampaignId.value = Number(id);
  if (!documentsByCampaign.value[activeCampaignId.value]) {
    loading.value = true;
    try {
      await loadDocuments(activeCampaignId.value);
    } catch (e) {
      error.value = e.response?.data?.error || e.message;
    } finally {
      loading.value = false;
    }
  }
};

const startEdit = doc => {
  editing.value = doc.id;
  editForm.value = {
    id: doc.id,
    kind: doc.kind,
    title: doc.title,
    content: doc.content,
    locale: doc.locale || '',
    position: doc.position || 0,
    active: doc.active !== false,
    isNew: false,
  };
};

const startNew = () => {
  editing.value = 'new';
  editForm.value = {
    id: null,
    kind: 'custom',
    title: '',
    content: '',
    locale: '',
    position: 0,
    active: true,
    isNew: true,
  };
};

const cancelEdit = () => {
  editing.value = null;
  editForm.value = {};
};

const saveEdit = async () => {
  if (!activeCampaignId.value) return;
  const payload = {
    kind: editForm.value.kind,
    title: editForm.value.title,
    content: editForm.value.content,
    locale: editForm.value.locale || null,
    position: Number(editForm.value.position) || 0,
    active: editForm.value.active,
  };
  savingId.value = editForm.value.id || 'new';
  error.value = null;
  try {
    if (editForm.value.isNew) {
      await OutreachKnowledgeAPI.create(activeCampaignId.value, payload);
    } else {
      await OutreachKnowledgeAPI.update(
        activeCampaignId.value,
        editForm.value.id,
        payload
      );
    }
    await loadDocuments(activeCampaignId.value);
    cancelEdit();
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.data?.message || e.message;
  } finally {
    savingId.value = null;
  }
};

const removeDoc = async doc => {
  if (
    !window.confirm(
      `Delete knowledge document "${doc.title}" (kind: ${doc.kind})?`
    )
  ) {
    return;
  }
  savingId.value = doc.id;
  try {
    await OutreachKnowledgeAPI.destroy(activeCampaignId.value, doc.id);
    await loadDocuments(activeCampaignId.value);
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    savingId.value = null;
  }
};

onMounted(refresh);
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
      v-if="loading && campaigns.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      Loading…
    </div>

    <div
      v-else-if="campaigns.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No outreach campaigns yet.
    </div>

    <div v-else class="flex flex-col gap-4">
      <div class="flex items-center gap-2">
        <label class="text-xs text-n-slate-11">Campaign:</label>
        <select
          :value="activeCampaignId || ''"
          class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
          @change="selectCampaign($event.target.value)"
        >
          <option v-for="c in campaigns" :key="c.id" :value="c.id">
            {{ c.name }} ({{ c.program_key }})
          </option>
        </select>
        <button
          type="button"
          class="ml-auto px-3 py-2 text-xs font-medium rounded bg-n-brand text-white hover:opacity-90"
          @click="startNew"
        >
          + New document
        </button>
      </div>

      <div v-if="editing" class="p-4 bg-white border rounded border-n-brand">
        <div class="mb-3 text-sm font-medium text-n-slate-12">
          {{
            editForm.isNew
              ? 'New knowledge document'
              : `Edit document #${editForm.id}`
          }}
        </div>
        <div class="grid grid-cols-3 gap-3 mb-3">
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Kind
            <select
              v-model="editForm.kind"
              class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
            >
              <option v-for="k in KINDS" :key="k" :value="k">{{ k }}</option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Locale (blank = global)
            <input
              v-model="editForm.locale"
              list="outreach-knowledge-locale-options"
              placeholder="pl, en, de…"
              class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
            />
            <datalist id="outreach-knowledge-locale-options">
              <option v-for="l in KNOWN_LOCALES" :key="l" :value="l" />
            </datalist>
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            Position
            <input
              v-model="editForm.position"
              type="number"
              class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
            />
          </label>
        </div>
        <label class="flex flex-col gap-1 mb-3 text-xs text-n-slate-11">
          Title
          <input
            v-model="editForm.title"
            class="reset-base px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 mb-3 text-xs text-n-slate-11">
          Content (markdown — composer ingests verbatim)
          <textarea
            v-model="editForm.content"
            rows="18"
            class="reset-base px-3 py-2 font-mono text-[13px] bg-white border rounded border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex items-center gap-2 mb-3 text-xs text-n-slate-11">
          <input v-model="editForm.active" type="checkbox" />
          Active (uncheck to hide from composer without deleting)
        </label>
        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="savingId"
            class="px-3 py-2 text-xs font-medium rounded bg-n-brand text-white disabled:opacity-50"
            @click="saveEdit"
          >
            {{ savingId ? 'Saving…' : 'Save' }}
          </button>
          <button
            type="button"
            class="px-3 py-2 text-xs text-n-slate-11 hover:underline"
            @click="cancelEdit"
          >
            Cancel
          </button>
        </div>
      </div>

      <div
        v-for="(list, kind) in groupedDocs"
        :key="kind"
        class="flex flex-col gap-2"
      >
        <h2
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
        >
          {{ kind }}
        </h2>
        <div
          v-for="d in list"
          :key="d.id"
          class="p-4 bg-white border rounded"
          :class="
            d.active === false ? 'border-n-weak opacity-60' : 'border-n-weak'
          "
        >
          <div class="flex items-start justify-between gap-3 mb-2">
            <div>
              <div class="text-sm font-medium text-n-slate-12">
                {{ d.title }}
              </div>
              <div class="mt-1 text-[11px] text-n-slate-11">
                <span class="px-1.5 py-0.5 font-mono rounded bg-n-slate-3">{{
                  d.locale || 'global'
                }}</span>
                <span
                  v-if="d.active === false"
                  class="ml-2 px-1.5 py-0.5 rounded bg-n-amber-3 text-n-amber-11"
                  >inactive</span
                >
              </div>
            </div>
            <div class="flex items-center gap-3 flex-shrink-0">
              <button
                type="button"
                class="text-xs font-medium text-n-brand hover:underline"
                @click="startEdit(d)"
              >
                Edit
              </button>
              <button
                type="button"
                :disabled="savingId === d.id"
                class="text-xs font-medium text-n-ruby-11 hover:underline"
                @click="removeDoc(d)"
              >
                Delete
              </button>
            </div>
          </div>
          <pre
            class="whitespace-pre-wrap text-[12px] font-mono text-n-slate-11 bg-n-slate-2 p-3 rounded max-h-60 overflow-auto"
            >{{ d.content }}</pre
          >
        </div>
      </div>
    </div>
  </div>
</template>
