<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const store = useStore();

const selectedConversationId = ref(null);
const isLoadingConversation = ref(false);

const uiFlags = computed(
  () => store.getters['contactConversations/getUIFlags']
);
const conversations = computed(() => {
  if (!props.contactId) return [];
  const list =
    store.getters['contactConversations/getContactConversation'](
      props.contactId
    ) || [];
  return [...list].sort((a, b) => {
    const lastA =
      a.last_non_activity_message?.created_at ||
      a.messages?.[a.messages.length - 1]?.created_at ||
      a.created_at ||
      0;
    const lastB =
      b.last_non_activity_message?.created_at ||
      b.messages?.[b.messages.length - 1]?.created_at ||
      b.created_at ||
      0;
    return lastB - lastA;
  });
});
const currentChat = computed(() => store.getters.getSelectedChat);

const refreshList = () => {
  if (!props.contactId) return;
  store.dispatch('contactConversations/get', props.contactId);
};

watch(
  () => props.contactId,
  id => {
    selectedConversationId.value = null;
    store.dispatch('clearSelectedState');
    if (id) refreshList();
  },
  { immediate: true }
);

const activateConversation = async conversation => {
  if (selectedConversationId.value === conversation.id) return;
  selectedConversationId.value = conversation.id;
  isLoadingConversation.value = true;
  try {
    // contactConversations records live in a separate state slice and
    // aren't visible to `getSelectedChat`, which looks them up in
    // `allConversations`. Always dispatch getConversation so the row
    // lands in the global list — otherwise setActiveChat sets
    // selectedChatId but the getter returns {} and ConversationBox
    // never renders.
    await store.dispatch('getConversation', conversation.id);
    let fresh = store.getters.getAllConversations.find(
      c => c.id === conversation.id
    );
    if (!fresh) {
      // getConversation silently swallows API failures (4xx, network)
      // and ReconnectService may have wiped allConversations mid-flight.
      // Fall back to the contactConversations record so the chat at
      // least renders instead of spinning forever.
      store.commit('UPDATE_CONVERSATION', conversation);
      fresh =
        store.getters.getAllConversations.find(c => c.id === conversation.id) ||
        conversation;
    }
    await store.dispatch('setActiveChat', { data: fresh });
    if (fresh.inbox_id) {
      store.dispatch('conversationLabels/get', fresh.id);
    }
  } finally {
    isLoadingConversation.value = false;
  }
};

// When the photographer has just one thread, skip the picker — open it
// straight away so the operator lands on messages with one click less.
watch(
  conversations,
  list => {
    if (list.length === 1 && selectedConversationId.value !== list[0].id) {
      activateConversation(list[0]);
    }
  },
  { immediate: true }
);

// Self-heal when the global allConversations gets wiped (websocket
// reconnect dispatches fetchAllConversations which may not bring 875
// back). Without this the spinner spins forever because getSelectedChat
// returns {} as long as the chat isn't in allConversations.
watch(
  () => currentChat.value?.id,
  (chatId, prevChatId) => {
    if (!chatId && selectedConversationId.value && prevChatId) {
      store.dispatch('getConversation', selectedConversationId.value);
    }
  }
);

onBeforeUnmount(() => {
  store.dispatch('clearSelectedState');
});

const formatDate = ts => {
  if (!ts) return '';
  const date = typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);
  return date.toLocaleString();
};

const lastMessagePreview = c => {
  const message =
    c.last_non_activity_message ||
    (c.messages && c.messages[c.messages.length - 1]);
  if (!message) return '';
  const raw = (message.content || '').replace(/\s+/g, ' ').trim();
  return raw.length > 140 ? `${raw.slice(0, 140)}…` : raw;
};

const statusTone = status => {
  switch (status) {
    case 'open':
      return 'bg-n-teal-3 text-n-teal-11';
    case 'pending':
      return 'bg-n-amber-3 text-n-amber-11';
    case 'resolved':
      return 'bg-n-slate-3 text-n-slate-11';
    case 'snoozed':
      return 'bg-n-brand-3 text-n-brand-11';
    default:
      return 'bg-n-slate-3 text-n-slate-11';
  }
};

const senderName = c =>
  c.meta?.sender?.name ||
  c.meta?.sender?.email ||
  c.additional_attributes?.mail_subject ||
  `#${c.id}`;
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col flex-1 min-h-0 bg-n-background">
    <div v-if="!contactId" class="p-6 text-sm text-n-slate-11">
      Ten fotograf nie ma jeszcze powiązanego kontaktu w Chatwoot — wątki
      pojawią się po pierwszej kampanii.
    </div>

    <template v-else>
      <div
        class="flex items-center justify-between gap-2 px-3 py-2 border-b border-n-weak"
      >
        <div class="text-xs text-n-slate-11">
          {{ conversations.length }} wątek/wątków
        </div>
        <button
          type="button"
          class="text-xs text-n-brand hover:underline disabled:opacity-60"
          :disabled="uiFlags.isFetching"
          @click="refreshList"
        >
          {{ uiFlags.isFetching ? 'Odświeżam…' : 'Odśwież' }}
        </button>
      </div>

      <div class="flex flex-1 min-h-0">
        <aside
          v-if="conversations.length > 1 || uiFlags.isFetching"
          class="flex flex-col w-64 flex-none border-r border-n-weak bg-n-surface-1 overflow-y-auto"
        >
          <div
            v-if="uiFlags.isFetching && !conversations.length"
            class="flex items-center justify-center p-6"
          >
            <Spinner />
          </div>
          <div
            v-else-if="!conversations.length"
            class="p-4 text-xs text-n-slate-11"
          >
            Brak wątków z tym kontaktem.
          </div>
          <template v-else>
            <button
              v-for="c in conversations"
              :key="c.id"
              type="button"
              class="flex flex-col gap-1 px-3 py-2 text-left border-b border-n-weak transition-colors"
              :class="
                selectedConversationId === c.id
                  ? 'bg-n-brand/10'
                  : 'hover:bg-n-alpha-1'
              "
              @click="activateConversation(c)"
            >
              <div class="flex items-center gap-2">
                <div class="flex-1 min-w-0">
                  <div class="text-xs font-medium text-n-slate-12 truncate">
                    {{ senderName(c) }}
                  </div>
                  <div class="text-[11px] text-n-slate-10 truncate">
                    #{{ c.id }} ·
                    {{
                      formatDate(
                        c.last_non_activity_message?.created_at || c.created_at
                      )
                    }}
                  </div>
                </div>
                <span
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded-full"
                  :class="statusTone(c.status)"
                >
                  {{ c.status }}
                </span>
              </div>
              <div
                v-if="lastMessagePreview(c)"
                class="text-[11px] text-n-slate-11 line-clamp-2"
              >
                {{ lastMessagePreview(c) }}
              </div>
            </button>
          </template>
        </aside>

        <div class="flex flex-col flex-1 min-w-0">
          <div
            v-if="!conversations.length && !uiFlags.isFetching"
            class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
          >
            Brak wątków z tym kontaktem.
          </div>
          <div
            v-else-if="!selectedConversationId"
            class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
          >
            Wybierz wątek z listy, aby otworzyć rozmowę.
          </div>
          <div
            v-else-if="isLoadingConversation || !currentChat.id"
            class="flex items-center justify-center flex-1"
          >
            <Spinner />
          </div>
          <ConversationBox
            v-else
            class="!flex-1 min-h-0 h-full"
            :inbox-id="currentChat.inbox_id || 0"
            is-inbox-view
            :is-contact-panel-open="false"
            :is-on-expanded-layout="false"
          />
        </div>
      </div>
    </template>
  </div>
</template>
