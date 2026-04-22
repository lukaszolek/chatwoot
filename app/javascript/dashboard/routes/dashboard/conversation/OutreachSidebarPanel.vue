<script setup>
import { ref, computed, watch } from 'vue';
import OutreachCampaignsAPI from 'dashboard/api/outreachCampaigns';
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

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');
const campaignLink = computed(() =>
  frontendURL(`accounts/${props.accountId}/outreach/campaigns`)
);
const profileLink = computed(() =>
  frontendURL(
    `accounts/${props.accountId}/outreach/photographers?q=${encodeURIComponent(
      context.value?.profile?.email || ''
    )}`
  )
);
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

    <div v-if="context.profile">
      <div class="text-xs uppercase tracking-wide text-n-slate-10 mb-1">
        Photographer profile
      </div>
      <div class="font-medium text-n-slate-12">
        {{ context.profile.business_name || context.profile.email }}
      </div>
      <div class="text-xs text-n-slate-11">
        {{ context.profile.owner_name }}
        <span v-if="context.profile.country_code">
          · {{ context.profile.country_code }}
        </span>
        <span v-if="context.profile.preferred_language">
          · {{ context.profile.preferred_language }}
        </span>
      </div>
      <router-link
        :to="profileLink"
        class="inline-block mt-1 text-xs font-medium text-n-brand hover:underline"
      >
        Open in Outreach →
      </router-link>
    </div>
  </div>
</template>
