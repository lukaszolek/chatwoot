<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

const props = defineProps({
  profile: { type: Object, required: true },
});

const emit = defineEmits(['close', 'contacted']);

const { t } = useI18n();
const store = useStore();

const channels = ref({});
const loading = ref(false);
const submitting = ref(false);
const error = ref('');
const selectedInboxId = ref(null);
const messageContent = ref('');

const availableChannels = computed(() =>
  Object.entries(channels.value)
    .map(([id, ch]) => ({ id: Number(id), ...ch }))
    .filter(ch => ch.available)
);

const canSubmit = computed(
  () =>
    selectedInboxId.value && messageContent.value.trim() && !submitting.value
);

const channelIcon = ch => {
  if (ch.channel_type === 'Channel::Instagram') return 'i-lucide-instagram';
  if (ch.channel_type === 'Channel::Email') return 'i-lucide-mail';
  return 'i-lucide-message-circle';
};

async function fetchChannels() {
  loading.value = true;
  try {
    const result = await store.dispatch('influencerProfiles/getConversations', {
      profileId: props.profile.id,
    });
    channels.value = result.channels || {};
    if (availableChannels.value.length) {
      selectedInboxId.value = availableChannels.value[0].id;
    }
  } finally {
    loading.value = false;
  }
}

async function handleSubmit() {
  if (!canSubmit.value) return;
  submitting.value = true;
  error.value = '';
  try {
    const updated = await store.dispatch('influencerProfiles/markContacted', {
      id: props.profile.id,
      inboxId: selectedInboxId.value,
      content: messageContent.value.trim(),
    });
    emit('contacted', updated);
    emit('close');
  } catch (err) {
    error.value =
      err?.response?.data?.error ||
      err?.message ||
      t('INFLUENCER.MARK_CONTACTED.ERROR');
  } finally {
    submitting.value = false;
  }
}

onMounted(fetchChannels);
</script>

<template>
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center bg-n-alpha-black2/50"
    @click.self="emit('close')"
  >
    <div class="w-full max-w-md rounded-xl bg-n-solid-1 shadow-xl">
      <div
        class="flex items-center justify-between border-b border-n-weak px-6 py-4"
      >
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('INFLUENCER.MARK_CONTACTED.TITLE') }}
        </h3>
        <button
          class="rounded-md p-1 text-n-slate-11 hover:bg-n-background"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <div class="p-6">
        <p class="mb-4 text-sm text-n-slate-11">
          {{
            t('INFLUENCER.MARK_CONTACTED.DESCRIPTION', {
              name: profile.fullname || profile.username,
            })
          }}
        </p>

        <div v-if="loading" class="py-4 text-center text-xs text-n-slate-10">
          <span
            class="i-lucide-loader-2 mr-1 inline-block size-3 animate-spin align-text-bottom"
          />
          {{ t('INFLUENCER.MESSAGING.LOADING') }}
        </div>

        <template v-else-if="availableChannels.length">
          <!-- Channel selector -->
          <div class="mb-4">
            <label class="mb-1 block text-xs text-n-slate-11">
              {{ t('INFLUENCER.MARK_CONTACTED.CHANNEL_LABEL') }}
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

          <!-- Message content -->
          <textarea
            v-model="messageContent"
            rows="4"
            class="mb-3 w-full resize-none rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand focus:outline-none"
            :placeholder="t('INFLUENCER.MARK_CONTACTED.MESSAGE_PLACEHOLDER')"
          />

          <p v-if="error" class="mb-3 text-xs text-red-600">{{ error }}</p>

          <div class="flex justify-end gap-2">
            <button
              class="rounded-lg border border-n-weak px-4 py-2 text-sm text-n-slate-11 hover:bg-n-background"
              @click="emit('close')"
            >
              {{ t('INFLUENCER.KANBAN.CANCEL') }}
            </button>
            <button
              class="flex items-center gap-1.5 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
              :disabled="!canSubmit"
              @click="handleSubmit"
            >
              <span
                v-if="submitting"
                class="i-lucide-loader-2 size-3.5 animate-spin"
              />
              <span v-else class="i-lucide-check size-3.5" />
              {{
                submitting
                  ? t('INFLUENCER.MARK_CONTACTED.SUBMITTING')
                  : t('INFLUENCER.MARK_CONTACTED.SUBMIT')
              }}
            </button>
          </div>
        </template>

        <p v-else class="py-4 text-center text-sm text-n-slate-10">
          {{ t('INFLUENCER.MESSAGING.NO_INBOXES') }}
        </p>
      </div>
    </div>
  </div>
</template>
