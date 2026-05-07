<script setup>
import { ref, computed, watch } from 'vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import { frontendURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  accountId: {
    type: [Number, String],
    required: true,
  },
});

const context = ref(null);
const loading = ref(false);
const error = ref(null);

// Language options the operator can switch the photographer to. Anything
// not on this list is still rendered (read-only) so we don't accidentally
// "lose" an exotic locale already stored in directory.
const LOCALE_OPTIONS = [
  'pl',
  'en',
  'de',
  'fr',
  'es',
  'it',
  'nl',
  'cs',
  'sk',
  'hu',
  'ro',
  'hr',
  'da',
  'fi',
  'sv',
  'el',
];

const editingLocale = ref(false);
const localeDraft = ref('');
const savingLocale = ref(false);
const runningAction = ref('');
const ACTION_LABELS = {
  needs_reply: 'Needs reply',
  resolve: 'Resolve',
  mark_auto_reply: 'Auto-reply',
  mark_bounced: 'Bounced',
  mark_opt_out: 'Opt-out / STOP',
};

const actionLabel = operation =>
  runningAction.value === operation ? 'Working…' : ACTION_LABELS[operation];

const fetchContext = async () => {
  if (!props.conversationId) return;
  loading.value = true;
  error.value = null;
  try {
    const res = await OutreachCampaignsAPI.conversationContext(
      props.conversationId
    );
    context.value = res.status === 204 ? null : res.data;
  } catch (e) {
    if (e.response?.status === 404 || e.response?.status === 204) {
      context.value = null;
    } else {
      error.value = e.response?.data?.error || e.message;
    }
  } finally {
    loading.value = false;
  }
};

watch(() => props.conversationId, fetchContext, { immediate: true });

const hasContext = computed(() => !!context.value?.campaign);
const profile = computed(() => context.value?.profile || null);

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');
const campaignLink = computed(() =>
  frontendURL(`accounts/${props.accountId}/outreach/campaigns`)
);
const profileLink = computed(() =>
  frontendURL(
    `accounts/${props.accountId}/outreach/photographers?q=${encodeURIComponent(
      profile.value?.email || ''
    )}`
  )
);

const websiteHref = computed(() => {
  const url = profile.value?.website;
  if (!url) return null;
  return /^https?:\/\//i.test(url) ? url : `https://${url}`;
});

// Pretty country / language labels via Intl.DisplayNames when available.
// Falls back to the raw code so the operator still sees something useful.
const displayNamesFor = (type, code, lang = 'en') => {
  if (!code) return null;
  try {
    const dn = new Intl.DisplayNames([lang], { type });
    return dn.of(type === 'region' ? code.toUpperCase() : code) || code;
  } catch {
    return code;
  }
};

const countryLabel = computed(() => {
  const code = profile.value?.country_code;
  if (!code) return null;
  const name = displayNamesFor('region', code);
  return name && name !== code.toUpperCase()
    ? `${code.toUpperCase()} — ${name}`
    : code.toUpperCase();
});

const languageLabel = computed(() => {
  const code =
    profile.value?.native_language || profile.value?.preferred_language;
  if (!code) return null;
  const name = displayNamesFor('language', code);
  return name && name !== code ? `${code} — ${name}` : code;
});

const localeOptionsForSelect = computed(() => {
  const current =
    profile.value?.native_language || profile.value?.preferred_language;
  const options = [...LOCALE_OPTIONS];
  if (current && !options.includes(current)) options.unshift(current);
  return options;
});

const startEditLocale = () => {
  localeDraft.value =
    profile.value?.native_language || profile.value?.preferred_language || '';
  editingLocale.value = true;
};
const cancelEditLocale = () => {
  editingLocale.value = false;
  localeDraft.value = '';
};
const saveLocale = async () => {
  if (!profile.value?.id) return;
  const current =
    profile.value.native_language || profile.value.preferred_language || '';
  if (localeDraft.value === current) {
    cancelEditLocale();
    return;
  }
  savingLocale.value = true;
  error.value = null;
  try {
    await OutreachPhotographersAPI.update(profile.value.id, {
      native_language: localeDraft.value,
      preferred_language: localeDraft.value,
    });
    await fetchContext();
    cancelEditLocale();
  } catch (e) {
    error.value =
      e.response?.data?.message || e.response?.data?.error || e.message;
  } finally {
    savingLocale.value = false;
  }
};

const runConversationAction = async operation => {
  if (!props.conversationId || runningAction.value) return;
  runningAction.value = operation;
  error.value = null;
  try {
    await OutreachCampaignsAPI.conversationAction(
      props.conversationId,
      operation
    );
    await fetchContext();
  } catch (e) {
    error.value =
      e.response?.data?.message || e.response?.data?.error || e.message;
  } finally {
    runningAction.value = '';
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div v-if="loading" class="p-3 text-xs text-n-slate-11">Loading…</div>
  <div v-else-if="error" class="p-3 text-xs rounded bg-n-ruby-3 text-n-ruby-11">
    {{ error }}
  </div>
  <div v-else-if="!hasContext" class="p-3 text-xs text-n-slate-11">
    Not linked to an outreach campaign.
  </div>
  <div v-else class="flex flex-col gap-3 p-3 text-sm">
    <div>
      <div class="text-xs uppercase tracking-wide text-n-slate-10 mb-1">
        Campaign
      </div>
      <div class="flex items-center gap-2">
        <router-link
          :to="campaignLink"
          class="font-medium text-n-brand hover:underline"
        >
          {{ context.campaign.name }}
        </router-link>
        <span
          class="px-1.5 py-0.5 text-[10px] font-medium rounded-full"
          :class="
            context.campaign.status === 'active'
              ? 'bg-n-teal-3 text-n-teal-11'
              : context.campaign.status === 'paused'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          {{ context.campaign.status }}
        </span>
      </div>
    </div>

    <div>
      <div class="text-xs uppercase tracking-wide text-n-slate-10 mb-1">
        Current stage
      </div>
      <div class="font-mono text-xs text-n-slate-12">
        {{ context.participant.current_stage_key }}
        <span v-if="context.participant.paused" class="ml-1 text-n-amber-11">
          · paused
        </span>
      </div>
      <div class="text-xs text-n-slate-11">
        since {{ formatDate(context.participant.stage_entered_at) }}
      </div>
    </div>

    <div class="grid grid-cols-2 gap-3 text-xs">
      <div>
        <div class="text-[10px] uppercase tracking-wide text-n-slate-10">
          Next action
        </div>
        <div class="text-n-slate-12">
          {{ formatDate(context.participant.next_action_at) }}
        </div>
      </div>
      <div>
        <div class="text-[10px] uppercase tracking-wide text-n-slate-10">
          Last sent
        </div>
        <div class="text-n-slate-12">
          {{ formatDate(context.participant.last_outbound_at) }}
        </div>
      </div>
    </div>

    <div v-if="profile">
      <div class="text-xs uppercase tracking-wide text-n-slate-10 mb-1">
        Photographer profile
      </div>
      <div class="font-medium text-n-slate-12">
        {{ profile.business_name || profile.email }}
      </div>
      <div v-if="profile.owner_name" class="text-xs text-n-slate-11">
        {{ profile.owner_name }}
      </div>

      <a
        v-if="websiteHref"
        :href="websiteHref"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-block mt-1 text-xs font-medium text-n-brand hover:underline break-all"
      >
        {{ profile.website }} ↗
      </a>

      <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 mt-2 text-xs">
        <dt class="text-n-slate-10">Country</dt>
        <dd class="text-n-slate-12">{{ countryLabel || '—' }}</dd>

        <dt class="text-n-slate-10">Language</dt>
        <dd
          v-if="!editingLocale"
          class="text-n-slate-12 flex items-center gap-2"
        >
          <span>{{ languageLabel || '—' }}</span>
          <button
            type="button"
            class="text-n-brand hover:underline"
            @click="startEditLocale"
          >
            Edit
          </button>
        </dd>
        <dd v-else class="flex items-center gap-2">
          <select
            v-model="localeDraft"
            class="!w-auto !mb-0 h-7 px-2 text-xs bg-white border rounded border-n-weak"
            :disabled="savingLocale"
          >
            <option value="">—</option>
            <option v-for="l in localeOptionsForSelect" :key="l" :value="l">
              {{ displayNamesFor('language', l) || l }} ({{ l }})
            </option>
          </select>
          <button
            type="button"
            class="text-n-brand font-medium hover:underline disabled:opacity-50"
            :disabled="savingLocale"
            @click="saveLocale"
          >
            {{ savingLocale ? 'Saving…' : 'Save' }}
          </button>
          <button
            type="button"
            class="text-n-slate-10 hover:underline"
            :disabled="savingLocale"
            @click="cancelEditLocale"
          >
            Cancel
          </button>
        </dd>
      </dl>

      <router-link
        :to="profileLink"
        class="inline-block mt-2 text-xs font-medium text-n-brand hover:underline"
      >
        Open in Outreach →
      </router-link>
    </div>

    <div class="pt-3 border-t border-n-weak">
      <div class="text-xs uppercase tracking-wide text-n-slate-10 mb-2">
        Outreach actions
      </div>
      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          class="h-8 px-2 text-xs font-medium rounded border border-n-weak text-n-slate-12 hover:bg-n-slate-2 disabled:opacity-50"
          :disabled="!!runningAction"
          @click="runConversationAction('needs_reply')"
        >
          {{ actionLabel('needs_reply') }}
        </button>
        <button
          type="button"
          class="h-8 px-2 text-xs font-medium rounded border border-n-weak text-n-slate-12 hover:bg-n-slate-2 disabled:opacity-50"
          :disabled="!!runningAction"
          @click="runConversationAction('resolve')"
        >
          {{ actionLabel('resolve') }}
        </button>
        <button
          type="button"
          class="h-8 px-2 text-xs font-medium rounded border border-n-weak text-n-slate-12 hover:bg-n-slate-2 disabled:opacity-50"
          :disabled="!!runningAction"
          @click="runConversationAction('mark_auto_reply')"
        >
          {{ actionLabel('mark_auto_reply') }}
        </button>
        <button
          type="button"
          class="h-8 px-2 text-xs font-medium rounded border border-n-weak text-n-slate-12 hover:bg-n-slate-2 disabled:opacity-50"
          :disabled="!!runningAction"
          @click="runConversationAction('mark_bounced')"
        >
          {{ actionLabel('mark_bounced') }}
        </button>
        <button
          type="button"
          class="col-span-2 h-8 px-2 text-xs font-medium rounded border border-n-ruby-5 text-n-ruby-11 hover:bg-n-ruby-2 disabled:opacity-50"
          :disabled="!!runningAction"
          @click="runConversationAction('mark_opt_out')"
        >
          {{ actionLabel('mark_opt_out') }}
        </button>
      </div>
    </div>
  </div>
</template>
