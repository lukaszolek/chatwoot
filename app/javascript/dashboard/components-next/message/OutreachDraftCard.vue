<script setup>
/* global axios */
import { computed, nextTick, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

const props = defineProps({
  messageId: { type: Number, required: true },
  conversationId: { type: Number, required: true },
  content: { type: String, default: '' },
  contentAttributes: { type: Object, default: () => ({}) },
  additionalAttributes: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['updated']);

const route = useRoute();
const accountId = computed(() => Number(route.params.accountId));

const baseUrl = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/conversations/${props.conversationId}/messages/${props.messageId}`
);

const status = computed(
  () => props.additionalAttributes?.draftStatus || 'pending'
);
const slot = computed(
  () => props.additionalAttributes?.templateSlot || 'unknown'
);
const locale = computed(() => props.additionalAttributes?.locale || '');
const iteration = computed(
  () => props.additionalAttributes?.iterationCount || 1
);
const regenerationHistory = computed(
  () => props.additionalAttributes?.regenerationHistory || []
);
const editHistory = computed(
  () => props.additionalAttributes?.editHistory || []
);
const toolCalls = computed(() => props.additionalAttributes?.toolCalls || []);

const isPending = computed(() => status.value === 'pending');
const isApproved = computed(() => status.value === 'approved');
const isRejected = computed(() => status.value === 'rejected');

const subject = ref(props.contentAttributes?.email?.subject || '');
const body = ref(props.content || '');
const bodyTextarea = ref(null);
const editingBody = ref(false);

const autoResize = () => {
  const el = bodyTextarea.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${el.scrollHeight}px`;
};

watch(body, () => nextTick(autoResize));
watch(
  () => props.content,
  newContent => {
    body.value = newContent || '';
    nextTick(autoResize);
  }
);
watch(
  () => props.contentAttributes?.email?.subject,
  newSubject => {
    subject.value = newSubject || '';
  }
);
// Initial sizing after mount
nextTick(autoResize);
const promptInput = ref('');
const learningNote = ref('');
const showPrompt = ref(false);
const showHistory = ref(false);
const busy = ref(null);
const error = ref(null);

const beginEdit = () => {
  editingBody.value = true;
};
const cancelEdit = () => {
  subject.value = props.contentAttributes?.email?.subject || '';
  body.value = props.content || '';
  editingBody.value = false;
  learningNote.value = '';
};

const saveEdit = async () => {
  busy.value = 'edit';
  error.value = null;
  try {
    await axios.patch(`${baseUrl.value}/edit_outreach_draft`, {
      subject: subject.value,
      body: body.value,
      learning_note: learningNote.value || undefined,
    });
    editingBody.value = false;
    learningNote.value = '';
    emit('updated');
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busy.value = null;
  }
};

const regenerate = async () => {
  if (!promptInput.value.trim()) {
    error.value = 'Wpisz prompt — np. "Skróć do 5 zdań"';
    return;
  }
  busy.value = 'regenerate';
  error.value = null;
  try {
    await axios.post(`${baseUrl.value}/regenerate_outreach_draft`, {
      operator_prompt: promptInput.value,
    });
    promptInput.value = '';
    showPrompt.value = false;
    emit('updated');
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busy.value = null;
  }
};

const approve = async () => {
  busy.value = 'approve';
  error.value = null;
  try {
    await axios.post(`${baseUrl.value}/approve_outreach_draft`);
    emit('updated');
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busy.value = null;
  }
};

const formatToolParams = params => {
  if (!params || typeof params !== 'object') return '';
  return Object.entries(params)
    .map(([k, v]) => `${k}: ${typeof v === 'string' ? JSON.stringify(v) : v}`)
    .join(', ');
};

const reject = async () => {
  const reason = window.prompt('Powód odrzucenia (eskalacja do operatora):');
  if (!reason) return;
  busy.value = 'reject';
  error.value = null;
  try {
    await axios.post(`${baseUrl.value}/reject_outreach_draft`, { reason });
    emit('updated');
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busy.value = null;
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div
    class="w-full max-w-3xl my-3 rounded-lg border-2 border-dashed bg-n-amber-2/30 border-n-amber-7 overflow-hidden"
  >
    <div
      class="flex items-center gap-2 px-4 py-2 text-xs font-medium border-b border-n-amber-7 bg-n-amber-3"
      :class="{
        'text-n-amber-11': isPending,
        'text-n-teal-11 bg-n-teal-3 border-n-teal-7': isApproved,
        'text-n-ruby-11 bg-n-ruby-3 border-n-ruby-7': isRejected,
      }"
    >
      <span>
        {{
          isApproved
            ? '✅ Outreach draft — wysłano'
            : isRejected
              ? '❌ Outreach draft — odrzucono'
              : '🤖 Outreach draft — czeka na zatwierdzenie'
        }}
      </span>
      <span class="ml-auto opacity-70">
        slot: {{ slot }} · locale: {{ locale }} · iter #{{ iteration }}
      </span>
    </div>

    <div class="p-4 bg-white">
      <div
        v-if="error"
        class="p-2 mb-2 text-xs rounded bg-n-ruby-3 text-n-ruby-11"
      >
        {{ error }}
      </div>

      <div
        v-if="slot === 'reply' && toolCalls.length"
        class="mb-3 p-3 rounded border border-n-teal-7 bg-n-teal-2"
      >
        <div
          class="text-[11px] uppercase tracking-wide font-semibold text-n-teal-11 mb-2"
        >
          🔧 Narzędzia, które LLM zawołał przy tworzeniu tej odpowiedzi ({{
            toolCalls.length
          }})
        </div>
        <ul class="space-y-1 text-[12px] text-n-slate-12">
          <li v-for="(tc, i) in toolCalls" :key="`tc-${i}`" class="font-mono">
            <strong>{{ tc.name }}</strong
            >({{ formatToolParams(tc.params) }})
          </li>
        </ul>
        <p class="mt-2 text-[11px] text-n-slate-11">
          Te calli już wykonały swoją akcję (odczyt profilu, zmiana consent
          itp.). Treść poniżej jest na ich podstawie.
        </p>
      </div>

      <label class="block mb-3">
        <span class="text-[11px] uppercase tracking-wide text-n-slate-11"
          >Subject</span
        >
        <input
          v-model="subject"
          :disabled="!isPending || !editingBody"
          class="reset-base w-full px-3 py-2 mt-1 text-sm border rounded border-n-weak text-n-slate-12"
          :class="{ 'bg-n-slate-2': !editingBody }"
        />
      </label>

      <label class="block mb-3">
        <span class="text-[11px] uppercase tracking-wide text-n-slate-11"
          >Body</span
        >
        <textarea
          ref="bodyTextarea"
          v-model="body"
          :disabled="!isPending || !editingBody"
          rows="4"
          class="reset-base w-full px-3 py-2 mt-1 font-mono text-[13px] border rounded border-n-weak text-n-slate-12 overflow-hidden resize-none leading-6"
          :class="{ 'bg-n-slate-2': !editingBody }"
          @input="autoResize"
        />
      </label>

      <label v-if="editingBody" class="block mb-3">
        <span class="text-[11px] uppercase tracking-wide text-n-slate-11">
          Notatka uczenia (opcjonalnie — dlaczego ta zmiana)
        </span>
        <input
          v-model="learningNote"
          placeholder='np. "Klient woli krótkie maile, bez liczb."'
          class="reset-base w-full px-3 py-2 mt-1 text-sm border rounded border-n-weak text-n-slate-12"
        />
      </label>

      <div v-if="showPrompt && isPending" class="p-3 mb-3 rounded bg-n-slate-2">
        <label
          class="block mb-2 text-[11px] uppercase tracking-wide text-n-slate-11"
        >
          Prompt do regeneracji
        </label>
        <textarea
          v-model="promptInput"
          rows="3"
          placeholder='np. "Skróć do 6 zdań i wymień konkretną liczbę 20%"'
          class="reset-base w-full px-3 py-2 text-sm border rounded border-n-weak text-n-slate-12"
        />
        <div class="flex items-center gap-2 mt-2">
          <button
            type="button"
            :disabled="busy === 'regenerate'"
            class="px-3 py-2 text-xs font-medium text-white rounded bg-n-brand disabled:opacity-50"
            @click="regenerate"
          >
            {{ busy === 'regenerate' ? 'Generuję…' : 'Wygeneruj ponownie' }}
          </button>
          <button
            type="button"
            class="px-3 py-2 text-xs text-n-slate-11 hover:underline"
            @click="
              showPrompt = false;
              promptInput = '';
            "
          >
            Anuluj
          </button>
        </div>
      </div>

      <div v-if="isPending" class="flex flex-wrap items-center gap-2">
        <button
          v-if="!editingBody"
          type="button"
          class="px-3 py-2 text-xs font-medium text-white rounded bg-n-teal-9 hover:bg-n-teal-10"
          :disabled="busy === 'approve'"
          @click="approve"
        >
          {{ busy === 'approve' ? 'Wysyłam…' : 'Wyślij' }}
        </button>
        <button
          v-if="!editingBody && !showPrompt"
          type="button"
          class="px-3 py-2 text-xs font-medium border rounded border-n-brand text-n-brand hover:bg-n-brand/10"
          @click="showPrompt = true"
        >
          Regeneruj z promptem
        </button>
        <button
          v-if="!editingBody"
          type="button"
          class="px-3 py-2 text-xs font-medium border rounded border-n-weak text-n-slate-12 hover:bg-n-slate-2"
          @click="beginEdit"
        >
          Edytuj ręcznie
        </button>
        <template v-if="editingBody">
          <button
            type="button"
            :disabled="busy === 'edit'"
            class="px-3 py-2 text-xs font-medium text-white rounded bg-n-brand disabled:opacity-50"
            @click="saveEdit"
          >
            {{
              busy === 'edit' ? 'Zapisuję…' : 'Zapisz zmiany (jako learning)'
            }}
          </button>
          <button
            type="button"
            class="px-3 py-2 text-xs text-n-slate-11 hover:underline"
            @click="cancelEdit"
          >
            Anuluj edycję
          </button>
        </template>
        <button
          v-if="!editingBody"
          type="button"
          class="ml-auto px-3 py-2 text-xs font-medium text-n-ruby-11 hover:underline"
          :disabled="busy === 'reject'"
          @click="reject"
        >
          Odrzuć (eskaluj)
        </button>
      </div>

      <div
        v-if="
          regenerationHistory.length || editHistory.length || toolCalls.length
        "
        class="mt-3 text-xs"
      >
        <button
          type="button"
          class="text-n-slate-11 hover:underline"
          @click="showHistory = !showHistory"
        >
          {{ showHistory ? '▼ Ukryj historię' : '▶ Pokaż historię' }}
          ({{ regenerationHistory.length }} regeneracji,
          {{ editHistory.length }} edycji, {{ toolCalls.length }} tool calls)
        </button>
        <div v-if="showHistory" class="mt-2 p-2 rounded bg-n-slate-2">
          <div v-if="toolCalls.length" class="mb-2">
            <div class="font-medium text-n-slate-12">Tool calls (od LLM):</div>
            <ul class="ml-4 list-disc">
              <li v-for="(tc, i) in toolCalls" :key="`tc-${i}`">
                <code>{{ tc.name }}</code
                >: {{ JSON.stringify(tc.params) }}
              </li>
            </ul>
          </div>
          <div v-if="regenerationHistory.length" class="mb-2">
            <div class="font-medium text-n-slate-12">Regeneracje:</div>
            <ul class="ml-4 list-disc">
              <li v-for="(h, i) in regenerationHistory" :key="`rg-${i}`">
                <strong>{{ h.at }}</strong
                >: prompt = "{{ h.operator_prompt }}" ({{ h.latency_ms }}ms)
              </li>
            </ul>
          </div>
          <div v-if="editHistory.length">
            <div class="font-medium text-n-slate-12">Edycje:</div>
            <ul class="ml-4 list-disc">
              <li v-for="(h, i) in editHistory" :key="`ed-${i}`">
                <strong>{{ h.at }}</strong
                >{{ h.learning_note ? `: ${h.learning_note}` : '' }}
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div v-else-if="isApproved" class="text-xs text-n-teal-11">
        Wysłane jako outgoing message.
      </div>
      <div v-else-if="isRejected" class="text-xs text-n-ruby-11">
        Powód: {{ additionalAttributes?.rejectedReason || '—' }}
      </div>
    </div>
  </div>
</template>
