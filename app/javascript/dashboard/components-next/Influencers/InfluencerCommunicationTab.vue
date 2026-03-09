<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

const props = defineProps({
  profile: { type: Object, required: true },
});

const emit = defineEmits(['update:profile']);

const { t } = useI18n();
const store = useStore();

const conversations = ref([]);
const channels = ref({});
const loading = ref(false);
const sending = ref(false);
const sendError = ref('');
const messageContent = ref('');
const messageSubject = ref('');
const selectedInboxId = ref(null);
const showCompose = ref(false);
const showLogForm = ref(false);
const logContent = ref('');
const logInboxId = ref(null);
const loggingSend = ref(false);
const messagesContainer = ref(null);
const showOriginal = ref(false);

const availableChannels = computed(() =>
  Object.entries(channels.value)
    .map(([id, ch]) => ({ id: Number(id), ...ch }))
    .filter(ch => ch.available)
);

const selectedChannelType = computed(() => {
  if (!selectedInboxId.value) return null;
  const ch = channels.value[selectedInboxId.value];
  return ch?.channel_type || null;
});

const isEmailChannel = computed(
  () => selectedChannelType.value === 'Channel::Email'
);

const canSend = computed(
  () => selectedInboxId.value && messageContent.value.trim() && !sending.value
);

const canLog = computed(
  () => logInboxId.value && logContent.value.trim() && !loggingSend.value
);

const allMessages = computed(() => {
  const msgs = [];
  conversations.value.forEach(conv => {
    (conv.messages || []).forEach(msg => {
      msgs.push({
        ...msg,
        inbox_name: conv.inbox?.name,
        channel_type: conv.inbox?.channel_type,
        conversation_display_id: conv.display_id,
      });
    });
  });
  return msgs.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
});

const hasAnyTranslation = computed(() =>
  allMessages.value.some(
    msg => Object.keys(msg.content_attributes?.translations || {}).length > 0
  )
);

function messageDisplayText(msg) {
  const translations = msg.content_attributes?.translations;
  if (!translations || !Object.keys(translations).length) return msg.content;
  if (showOriginal.value) {
    // Original = what was actually sent to the influencer (msg.content)
    return msg.content;
  }
  // Default: show operator's language (stored in translations)
  const operatorText = Object.values(translations)[0];
  return operatorText || msg.content;
}

function hasTranslation(msg) {
  return Object.keys(msg.content_attributes?.translations || {}).length > 0;
}

const channelIcon = ch => {
  const type = ch.channel_type || ch;
  if (type === 'Channel::Instagram') return 'i-lucide-instagram';
  if (type === 'Channel::Email') return 'i-lucide-mail';
  return 'i-lucide-message-circle';
};

function formatTime(dateStr) {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now - date;
  const diffDays = Math.floor(diffMs / 86400000);
  if (diffDays === 0)
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (diffDays === 1) return t('INFLUENCER.COMMUNICATION.YESTERDAY');
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}

function scrollToBottom() {
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
  }
}

async function fetchMessages() {
  loading.value = true;
  try {
    const [msgData, convData] = await Promise.all([
      store.dispatch('influencerProfiles/getConversationMessages', {
        profileId: props.profile.id,
      }),
      store.dispatch('influencerProfiles/getConversations', {
        profileId: props.profile.id,
      }),
    ]);
    conversations.value = msgData || [];
    channels.value = convData.channels || {};
    if (availableChannels.value.length && !selectedInboxId.value) {
      selectedInboxId.value = availableChannels.value[0].id;
    }
    if (availableChannels.value.length && !logInboxId.value) {
      logInboxId.value = availableChannels.value[0].id;
    }
    await nextTick();
    scrollToBottom();
  } finally {
    loading.value = false;
  }
}

async function handleSend() {
  if (!canSend.value) return;
  sending.value = true;
  sendError.value = '';
  try {
    await store.dispatch('influencerProfiles/sendMessage', {
      profileId: props.profile.id,
      inboxId: selectedInboxId.value,
      content: messageContent.value.trim(),
      subject: isEmailChannel.value ? messageSubject.value.trim() : undefined,
    });
    messageContent.value = '';
    showCompose.value = false;
    await fetchMessages();
  } catch (err) {
    sendError.value =
      err?.response?.data?.error || err?.message || 'Failed to send';
  } finally {
    sending.value = false;
  }
}

async function handleLogMessage() {
  if (!canLog.value) return;
  loggingSend.value = true;
  try {
    const updated = await store.dispatch('influencerProfiles/logMessage', {
      profileId: props.profile.id,
      inboxId: logInboxId.value,
      content: logContent.value.trim(),
    });
    logContent.value = '';
    showLogForm.value = false;
    emit('update:profile', updated);
    await fetchMessages();
  } catch {
    // silent
  } finally {
    loggingSend.value = false;
  }
}

function openConversation(displayId) {
  const accountId =
    props.profile.account_id || store.getters.getCurrentAccountId;
  const url = `/app/accounts/${accountId}/conversations/${displayId}`;
  window.open(url, '_blank');
}

onMounted(fetchMessages);
watch(() => props.profile.id, fetchMessages);
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex h-full flex-col">
    <!-- Action buttons -->
    <div class="mb-3 flex items-center gap-2">
      <button
        v-if="availableChannels.length && !showCompose"
        class="flex items-center gap-1 rounded-lg bg-n-brand px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
        @click="
          showCompose = true;
          showLogForm = false;
        "
      >
        <span class="i-lucide-send size-3" />
        {{ t('INFLUENCER.MESSAGING.NEW_MESSAGE') }}
      </button>
      <button
        v-if="availableChannels.length && !showLogForm"
        class="flex items-center gap-1 rounded-lg border border-n-weak px-3 py-1.5 text-xs font-medium text-n-slate-11 hover:bg-n-background"
        @click="
          showLogForm = true;
          showCompose = false;
        "
      >
        <span class="i-lucide-notebook-pen size-3" />
        {{ t('INFLUENCER.COMMUNICATION.LOG_MESSAGE') }}
      </button>
      <!-- Translation toggle -->
      <button
        v-if="hasAnyTranslation"
        class="ml-auto flex items-center gap-1 rounded-lg border px-2.5 py-1.5 text-xs font-medium transition-colors"
        :class="
          showOriginal
            ? 'border-n-weak text-n-slate-11 hover:bg-n-background'
            : 'border-n-brand bg-n-brand/10 text-n-brand'
        "
        :title="t('INFLUENCER.COMMUNICATION.TOGGLE_TRANSLATION')"
        @click="showOriginal = !showOriginal"
      >
        <span class="i-lucide-languages size-3.5" />
        {{
          showOriginal
            ? t('INFLUENCER.COMMUNICATION.SHOW_TRANSLATED')
            : t('INFLUENCER.COMMUNICATION.SHOW_ORIGINAL')
        }}
      </button>
    </div>

    <!-- Compose box -->
    <div
      v-if="showCompose"
      class="mb-4 rounded-lg border border-n-weak bg-n-background p-3"
    >
      <div class="mb-3">
        <label class="mb-1 block text-xs text-n-slate-11">
          {{ t('INFLUENCER.MESSAGING.SEND_VIA') }}
        </label>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="ch in availableChannels"
            :key="ch.id"
            class="flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium transition-colors"
            :class="
              selectedInboxId === ch.id
                ? 'border-n-brand bg-n-brand/10 text-n-brand'
                : 'border-n-weak text-n-slate-11 hover:bg-n-slate-2'
            "
            @click="selectedInboxId = ch.id"
          >
            <span :class="channelIcon(ch)" class="size-3.5" />
            {{ ch.name }}
          </button>
        </div>
      </div>

      <input
        v-if="isEmailChannel"
        v-model="messageSubject"
        type="text"
        class="mb-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand focus:outline-none"
        :placeholder="t('INFLUENCER.MESSAGING.SUBJECT_PLACEHOLDER')"
      />

      <textarea
        v-model="messageContent"
        rows="3"
        class="mb-2 w-full resize-none rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand focus:outline-none"
        :placeholder="t('INFLUENCER.MESSAGING.PLACEHOLDER')"
      />

      <div class="flex items-center justify-between">
        <button
          class="text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="showCompose = false"
        >
          {{ t('INFLUENCER.KANBAN.CANCEL') }}
        </button>
        <button
          class="flex items-center gap-1 rounded-lg bg-n-brand px-4 py-1.5 text-xs font-medium text-white hover:opacity-90 disabled:opacity-50"
          :disabled="!canSend"
          @click="handleSend"
        >
          <span v-if="sending" class="i-lucide-loader-2 size-3 animate-spin" />
          <span v-else class="i-lucide-send size-3" />
          {{
            sending
              ? t('INFLUENCER.MESSAGING.SENDING')
              : t('INFLUENCER.MESSAGING.SEND')
          }}
        </button>
      </div>
      <p v-if="sendError" class="mt-2 text-xs text-red-600">{{ sendError }}</p>
    </div>

    <!-- Log manual message form -->
    <div
      v-if="showLogForm"
      class="mb-4 rounded-lg border border-n-weak bg-n-background p-3"
    >
      <p class="mb-2 text-xs text-n-slate-11">
        {{ t('INFLUENCER.COMMUNICATION.LOG_DESCRIPTION') }}
      </p>
      <div class="mb-3 flex flex-wrap gap-2">
        <button
          v-for="ch in availableChannels"
          :key="ch.id"
          class="flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium transition-colors"
          :class="
            logInboxId === ch.id
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak text-n-slate-11 hover:bg-n-slate-2'
          "
          @click="logInboxId = ch.id"
        >
          <span :class="channelIcon(ch)" class="size-3.5" />
          {{ ch.name }}
        </button>
      </div>
      <textarea
        v-model="logContent"
        rows="3"
        class="mb-2 w-full resize-none rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand focus:outline-none"
        :placeholder="t('INFLUENCER.COMMUNICATION.LOG_PLACEHOLDER')"
      />
      <div class="flex items-center justify-between">
        <button
          class="text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="showLogForm = false"
        >
          {{ t('INFLUENCER.KANBAN.CANCEL') }}
        </button>
        <button
          class="flex items-center gap-1 rounded-lg bg-n-slate-12 px-4 py-1.5 text-xs font-medium text-n-solid-1 hover:opacity-90 disabled:opacity-50"
          :disabled="!canLog"
          @click="handleLogMessage"
        >
          <span
            v-if="loggingSend"
            class="i-lucide-loader-2 size-3 animate-spin"
          />
          <span v-else class="i-lucide-notebook-pen size-3" />
          {{ t('INFLUENCER.COMMUNICATION.LOG_SUBMIT') }}
        </button>
      </div>
    </div>

    <!-- Messages list -->
    <div v-if="loading" class="py-8 text-center text-xs text-n-slate-10">
      <span
        class="i-lucide-loader-2 mr-1 inline-block size-3 animate-spin align-text-bottom"
      />
      {{ t('INFLUENCER.MESSAGING.LOADING') }}
    </div>

    <div
      v-else-if="allMessages.length"
      ref="messagesContainer"
      class="flex-1 space-y-3 overflow-auto"
    >
      <div
        v-for="msg in allMessages"
        :key="msg.id"
        class="flex"
        :class="
          msg.message_type === 'outgoing' ? 'justify-end' : 'justify-start'
        "
      >
        <div
          class="max-w-[85%] rounded-lg px-3 py-2"
          :class="
            msg.message_type === 'outgoing'
              ? 'bg-n-brand/10 text-n-slate-12'
              : 'bg-n-background text-n-slate-12'
          "
        >
          <p class="whitespace-pre-wrap text-sm">
            {{ messageDisplayText(msg) }}
          </p>
          <div class="mt-1 flex items-center gap-2 text-[10px] text-n-slate-10">
            <span :class="channelIcon(msg)" class="size-2.5" />
            <span>{{ msg.inbox_name }}</span>
            <span
              v-if="msg.content_attributes?.manual_log"
              class="rounded bg-n-amber-2 px-1 text-n-amber-11"
            >
              {{ t('INFLUENCER.COMMUNICATION.MANUAL_BADGE') }}
            </span>
            <span
              v-if="hasTranslation(msg) && !showOriginal"
              class="rounded bg-n-blue-2 px-1 text-n-blue-11"
            >
              {{ t('INFLUENCER.COMMUNICATION.TRANSLATED_BADGE') }}
            </span>
            <span>{{ formatTime(msg.created_at) }}</span>
            <button
              class="i-lucide-external-link size-2.5 text-n-slate-10 hover:text-n-brand"
              :title="t('INFLUENCER.COMMUNICATION.OPEN_CONVERSATION')"
              @click="openConversation(msg.conversation_display_id)"
            />
          </div>
        </div>
      </div>
    </div>

    <p v-else-if="!loading" class="py-8 text-center text-xs text-n-slate-10">
      {{ t('INFLUENCER.MESSAGING.NO_CONVERSATIONS') }}
    </p>
  </div>
</template>
