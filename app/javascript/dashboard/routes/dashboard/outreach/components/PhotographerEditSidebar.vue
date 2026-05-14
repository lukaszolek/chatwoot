<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'vuex';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import OutreachThreadsPanel from './OutreachThreadsPanel.vue';

const props = defineProps({
  profile: { type: Object, default: null },
  countryOptions: { type: Array, default: () => [] },
  localeOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const activeTab = ref('info');

const TABS = [
  { key: 'info', label: 'Dane' },
  { key: 'threads', label: 'Wątki' },
];

// Reset to the info tab whenever a different photographer is opened so
// operators don't accidentally see threads for the previous profile.
watch(
  () => props.profile?.id,
  () => {
    activeTab.value = 'info';
  }
);

const closeSidebar = () => {
  store.dispatch('clearSelectedState');
  emit('close');
};

const CONSENT_OPTIONS = [
  { value: 'unknown', label: 'No answer yet', tone: 'slate' },
  { value: 'granted', label: 'Consent given', tone: 'teal' },
  { value: 'declined', label: 'Refused', tone: 'ruby' },
];

const STATUS_OPTIONS = [
  'imported',
  'qualified',
  'contacted',
  'replied',
  'interested',
  'signed_up',
  'declined',
  'do_not_contact',
  'completed',
];

// PII fields here are EDITABLE — backend routes them through
// Outreach::PhotographerDirectory::ProfileWriter, which writes to the
// secondary photographer_directory DB. Chatwoot keeps no copies; reads
// of profile.email etc. delegate live to the directory row.
//
// If the directory DB lacks UPDATE grants for any of these columns, the
// backend returns 422 with `error: 'directory_grants_missing'` — UI
// surfaces the hint (run db/photographer_directory_grants/*.sql).
const form = ref({});
const saving = ref(false);
const error = ref(null);
const errorHint = ref(null);

const directoryUrl = computed(() => {
  if (!props.profile?.external_id) return null;
  return `https://framky.com/pl-pl/fotograf/${props.profile.external_id}`;
});

const profileLocale = profile =>
  profile?.native_language ||
  profile?.directory_preferred_language ||
  profile?.preferred_language ||
  '';

const hydrate = profile => {
  if (!profile) {
    form.value = {};
    return;
  }
  form.value = {
    // PII — written through ProfileWriter to directory
    email: profile.email || '',
    business_name: profile.business_name || '',
    owner_name: profile.owner_name || '',
    website: profile.website || '',
    country_code: profile.country_code || '',
    locale: profileLocale(profile),
    instagram_handle: profile.instagram_handle || '',
    phone: profile.phone || '',

    // Chatwoot-side outreach state — written locally
    marketing_consent_state: profile.marketing_consent_state || 'unknown',
    partnership_status: profile.partnership_status,
    notes: profile.notes || '',
    tags: profile.tags || [],
  };
  error.value = null;
  errorHint.value = null;
};

watch(() => props.profile, hydrate, { immediate: true });

// Only send PII fields that actually changed — avoids noise in the
// directory audit log and avoids re-validating untouched fields.
const piiChanges = () => {
  if (!props.profile) return {};
  const fields = [
    'email',
    'business_name',
    'owner_name',
    'website',
    'country_code',
    'instagram_handle',
    'phone',
  ];
  const changed = {};
  fields.forEach(f => {
    const before = (props.profile[f] || '').toString();
    const after = (form.value[f] || '').toString();
    if (before !== after) changed[f] = after;
  });

  const beforeLocale = profileLocale(props.profile).toString();
  const afterLocale = (form.value.locale || '').toString();
  if (beforeLocale !== afterLocale) {
    changed.native_language = afterLocale;
    changed.preferred_language = afterLocale;
  }

  return changed;
};

const save = async () => {
  if (!props.profile) return;
  saving.value = true;
  error.value = null;
  errorHint.value = null;
  try {
    const payload = {
      ...piiChanges(),
      marketing_consent_state: form.value.marketing_consent_state,
      partnership_status: form.value.partnership_status,
      notes: form.value.notes,
      tags: form.value.tags,
    };
    const { data } = await OutreachPhotographersAPI.update(
      props.profile.id,
      payload
    );
    emit('saved', data);
    emit('close');
  } catch (e) {
    const body = e.response?.data || {};
    error.value = body.message || body.error || e.message;
    errorHint.value = body.hint || null;
  } finally {
    saving.value = false;
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <transition name="drawer">
    <aside
      v-if="profile"
      class="fixed top-0 right-0 bottom-0 z-50 max-w-[95vw] flex flex-col bg-white border-l border-n-weak shadow-2xl transition-[width] duration-200 ease-out"
      :class="activeTab === 'threads' ? 'w-[960px]' : 'w-[480px]'"
    >
      <header
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <div>
          <div class="text-sm font-semibold text-n-slate-12">
            Edit photographer
          </div>
          <div class="text-xs text-n-slate-11">
            {{ profile.email || '(directory offline)' }}
          </div>
        </div>
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:underline"
          @click="closeSidebar"
        >
          Close
        </button>
      </header>

      <nav
        class="flex items-center gap-1 px-2 border-b border-n-weak bg-n-surface-1"
      >
        <button
          v-for="tab in TABS"
          :key="tab.key"
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
          :class="
            activeTab === tab.key
              ? 'border-n-brand text-n-brand'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </nav>

      <div
        v-show="activeTab === 'info' && error"
        class="px-4 py-2 text-sm bg-n-ruby-3 text-n-ruby-11"
      >
        <div>{{ error }}</div>
        <div v-if="errorHint" class="mt-1 text-xs">{{ errorHint }}</div>
      </div>

      <div
        v-show="activeTab === 'info'"
        class="flex-1 overflow-y-auto p-4 flex flex-col gap-4 text-sm"
      >
        <!-- PII block — edits propagate to photographer-directory via ProfileWriter -->
        <section class="flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <div
              class="text-[11px] uppercase tracking-wide font-semibold text-n-slate-11"
            >
              Dane fotografa (źródło: photographer-directory)
            </div>
            <a
              v-if="directoryUrl"
              :href="directoryUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="text-[11px] text-n-brand hover:underline"
            >
              Otwórz w directory ↗
            </a>
          </div>
          <div v-if="!profile.directory_linked" class="text-xs text-n-ruby-11">
            ⚠️ Directory niedostępne — pola PII nie zostały załadowane. Sprawdź
            VPN / secondary DB.
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Email</span>
            <input
              v-model="form.email"
              type="email"
              class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
            />
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">Business name</span>
              <input
                v-model="form.business_name"
                type="text"
                class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">Owner name</span>
              <input
                v-model="form.owner_name"
                type="text"
                class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
              />
            </label>
          </div>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Website</span>
            <input
              v-model="form.website"
              type="url"
              class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Instagram handle</span>
            <input
              v-model="form.instagram_handle"
              type="text"
              class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
            />
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">Country (2-letter)</span>
              <input
                v-model="form.country_code"
                type="text"
                maxlength="2"
                list="photographer-countries"
                class="reset-base w-full h-9 px-3 bg-white uppercase border rounded border-n-weak"
              />
              <datalist id="photographer-countries">
                <option v-for="c in countryOptions" :key="c" :value="c" />
              </datalist>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">Locale</span>
              <input
                v-model="form.locale"
                type="text"
                maxlength="5"
                list="photographer-locales"
                class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
              />
              <datalist id="photographer-locales">
                <option v-for="l in localeOptions" :key="l" :value="l" />
              </datalist>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">Phone</span>
              <input
                v-model="form.phone"
                type="tel"
                class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
              />
            </label>
          </div>
        </section>

        <!-- Chatwoot-side outreach state -->
        <section class="flex flex-col gap-3 pt-3 border-t border-n-weak">
          <div
            class="text-[11px] uppercase tracking-wide font-semibold text-n-slate-11"
          >
            Stan outreachu (chatwoot-side)
          </div>

          <fieldset class="flex flex-col gap-2">
            <legend class="text-xs text-n-slate-11">
              Marketing consent (tri-state)
            </legend>
            <div class="flex flex-col gap-1">
              <label
                v-for="opt in CONSENT_OPTIONS"
                :key="opt.value"
                class="flex items-center gap-2 cursor-pointer"
              >
                <input
                  v-model="form.marketing_consent_state"
                  type="radio"
                  :value="opt.value"
                  name="consent-state"
                />
                <span
                  class="px-2 py-0.5 text-xs font-medium rounded-full"
                  :class="{
                    'bg-n-teal-3 text-n-teal-11': opt.tone === 'teal',
                    'bg-n-ruby-3 text-n-ruby-11': opt.tone === 'ruby',
                    'bg-n-slate-3 text-n-slate-11': opt.tone === 'slate',
                  }"
                >
                  {{ opt.label }}
                </span>
              </label>
            </div>
          </fieldset>

          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Partnership status</span>
            <select
              v-model="form.partnership_status"
              class="reset-base w-full h-9 px-3 bg-white border rounded border-n-weak"
            >
              <option v-for="s in STATUS_OPTIONS" :key="s" :value="s">
                {{ s }}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">Notes (operator-only)</span>
            <textarea
              v-model="form.notes"
              rows="4"
              class="reset-base w-full !mb-0 px-3 py-2 bg-white border rounded border-n-weak"
            />
          </label>
        </section>
      </div>

      <OutreachThreadsPanel
        v-show="activeTab === 'threads'"
        :contact-id="profile.contact_id"
      />

      <footer
        v-show="activeTab === 'info'"
        class="flex items-center justify-between gap-2 px-4 py-3 border-t border-n-weak"
      >
        <span class="text-xs text-n-slate-11">
          Status: <strong>{{ profile.partnership_status }}</strong>
        </span>
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="px-3 py-1.5 text-sm border rounded border-n-weak"
            :disabled="saving"
            @click="closeSidebar"
          >
            Cancel
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-sm font-medium text-white rounded bg-n-brand hover:opacity-90 disabled:opacity-60"
            :disabled="saving"
            @click="save"
          >
            {{ saving ? 'Saving…' : 'Save' }}
          </button>
        </div>
      </footer>
    </aside>
  </transition>
</template>

<style scoped>
.drawer-enter-active,
.drawer-leave-active {
  transition: transform 0.18s ease;
}
.drawer-enter-from,
.drawer-leave-to {
  transform: translateX(100%);
}
</style>
