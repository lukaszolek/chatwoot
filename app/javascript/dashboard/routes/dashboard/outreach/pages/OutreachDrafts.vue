<script setup>
import { ref, onMounted } from 'vue';
import OutreachDraftsAPI from 'dashboard/api/outreachDrafts';

const drafts = ref([]);
const loading = ref(false);
const error = ref(null);

const fetchAll = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await OutreachDraftsAPI.get();
    drafts.value = data || [];
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const act = async (id, action) => {
  try {
    await OutreachDraftsAPI[action](id);
    await fetchAll();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  }
};

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');

onMounted(fetchAll);
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
      v-else-if="drafts.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No drafts awaiting review.
    </div>
    <div v-else class="flex flex-col gap-4">
      <article
        v-for="d in drafts"
        :key="d.id"
        class="p-4 bg-white border rounded border-n-weak"
      >
        <header class="flex items-center justify-between mb-2">
          <div class="text-sm font-medium text-n-slate-12">
            <span v-if="d.participant?.profile">
              {{
                d.participant.profile.business_name ||
                d.participant.profile.email
              }}
              —
            </span>
            <span class="font-normal text-n-slate-11">
              slot {{ d.template_slot }} · {{ d.locale }}
            </span>
          </div>
          <div v-if="d.llm_decision" class="text-xs text-n-slate-11">
            {{ d.llm_decision.model }} · conf
            <strong>{{ (d.llm_decision.confidence * 100).toFixed(0) }}%</strong>
            · routed <code>{{ d.llm_decision.routed_to }}</code>
          </div>
        </header>
        <div class="mb-3 text-sm">
          <div class="mb-1 font-medium text-n-slate-12">{{ d.subject }}</div>
          <div
            class="p-3 overflow-auto font-mono text-xs whitespace-pre-wrap rounded bg-n-slate-2 text-n-slate-11 max-h-60"
          >
            {{ d.body }}
          </div>
        </div>
        <footer class="flex items-center justify-between">
          <div class="text-xs text-n-slate-11">
            created {{ formatDate(d.created_at) }} · iteration
            {{ d.iteration_count || 0 }}
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="px-3 py-1.5 text-xs font-medium rounded bg-n-teal-9 text-white hover:bg-n-teal-10"
              @click="act(d.id, 'approve')"
            >
              Approve & send
            </button>
            <button
              type="button"
              class="px-3 py-1.5 text-xs font-medium rounded border border-n-ruby-7 text-n-ruby-11 hover:bg-n-ruby-3"
              @click="act(d.id, 'reject')"
            >
              Reject (escalate)
            </button>
          </div>
        </footer>
      </article>
    </div>
  </div>
</template>
