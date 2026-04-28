<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import OutreachDirectoryAPI from 'dashboard/api/outreachDirectory';
import PhotographerEditSidebar from '../components/PhotographerEditSidebar.vue';

// ---------- Unified search state ----------
const profiles = ref([]);
const profilesTotal = ref(0);
const directoryResults = ref([]);
const directoryTotal = ref(0);
const loading = ref(false);
const error = ref(null);
const busyRowKey = ref(null);
const importSummary = ref(null);

const filters = ref({ q: '', status: '', country_code: '', locale: '' });

const countryOptions = ref([]);
const localeOptions = ref([]);

const fetchFacets = async () => {
  try {
    const { data } = await OutreachPhotographersAPI.facets();
    countryOptions.value = data.country_codes || [];
    localeOptions.value = data.locales || [];
  } catch (e) {
    // Non-critical — autocomplete just falls back to an empty list.
  }
};

const STATUSES = [
  { value: '', label: 'All statuses' },
  { value: 'imported', label: 'Imported' },
  { value: 'qualified', label: 'Qualified' },
  { value: 'contacted', label: 'Contacted' },
  { value: 'replied', label: 'Replied' },
  { value: 'interested', label: 'Interested' },
  { value: 'signed_up', label: 'Signed up' },
  { value: 'declined', label: 'Declined' },
  { value: 'do_not_contact', label: 'Do not contact' },
  { value: 'completed', label: 'Completed' },
];

const fetchProfiles = async () => {
  const { data } = await OutreachPhotographersAPI.get(1, filters.value);
  profiles.value = data.data || [];
  profilesTotal.value = data.meta?.total || 0;
};

const fetchDirectory = async () => {
  // Only hit the directory when the operator has typed a query —
  // otherwise we'd pull the entire directory on every page load.
  if (
    !filters.value.q &&
    !filters.value.country_code &&
    !filters.value.locale
  ) {
    directoryResults.value = [];
    directoryTotal.value = 0;
    return;
  }
  const { data } = await OutreachDirectoryAPI.search(1, {
    q: filters.value.q,
    country_code: filters.value.country_code,
    locale: filters.value.locale,
  });
  directoryResults.value = data.data || [];
  directoryTotal.value = data.meta?.total || 0;
};

const runSearch = async () => {
  loading.value = true;
  error.value = null;
  try {
    await Promise.all([fetchProfiles(), fetchDirectory()]);
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

// Unified row list — local profiles first, then directory rows that
// aren't already enrolled (those are collapsed into the profile row).
const rows = computed(() => {
  const out = [];
  const seenExternalIds = new Set();
  profiles.value.forEach(p => {
    out.push({
      key: `profile-${p.id}`,
      type: 'profile',
      profile: p,
      email: p.email,
      business_name: p.business_name,
      owner_name: p.owner_name,
      website: p.website,
      country_code: p.country_code,
      preferred_language: p.preferred_language,
    });
    if (p.external_id) seenExternalIds.add(String(p.external_id));
  });
  directoryResults.value.forEach(r => {
    if (seenExternalIds.has(String(r.id))) return;
    if (r.already_enrolled) return;
    out.push({
      key: `dir-${r.id}`,
      type: 'directory',
      directory: r,
      email: r.email,
      business_name: r.business_name,
      owner_name: r.owner_name,
      website: r.website,
      country_code: r.country_code,
      preferred_language: r.preferred_language,
    });
  });
  return out;
});

const totalShown = computed(() => rows.value.length);

// ---------- Actions ----------
const optOut = async profile => {
  if (!window.confirm(`Opt ${profile.email} out of outreach?`)) return;
  busyRowKey.value = `profile-${profile.id}`;
  try {
    await OutreachPhotographersAPI.optOut(profile.id);
    await runSearch();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busyRowKey.value = null;
  }
};

const startCampaign = async row => {
  busyRowKey.value = row.key;
  importSummary.value = null;
  error.value = null;
  try {
    const { data } = await OutreachDirectoryAPI.import([row.directory.id]);
    importSummary.value = data.result;
    await runSearch();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    busyRowKey.value = null;
  }
};

// ---------- Add photographer manually ----------
function blankAddForm() {
  return {
    email: '',
    business_name: '',
    owner_name: '',
    website: '',
    country_code: '',
    preferred_language: '',
    instagram_handle: '',
    enroll: true,
  };
}
const showAddForm = ref(false);
const addSaving = ref(false);
const addForm = ref(blankAddForm());
const submitAdd = async () => {
  addSaving.value = true;
  error.value = null;
  try {
    const { enroll, ...payload } = addForm.value;
    await OutreachPhotographersAPI.create(payload, enroll);
    showAddForm.value = false;
    addForm.value = blankAddForm();
    await runSearch();
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.data?.message || e.message;
  } finally {
    addSaving.value = false;
  }
};

// ---------- Edit sidebar ----------
const editingProfile = ref(null);
const openEdit = profile => {
  editingProfile.value = profile;
};
const closeEdit = () => {
  editingProfile.value = null;
};
const onSaved = () => {
  runSearch();
};

const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');

const websiteHref = url => {
  if (!url) return null;
  return /^https?:\/\//i.test(url) ? url : `https://${url}`;
};

onMounted(() => {
  runSearch();
  fetchFacets();
});

let searchTimer = null;
watch(
  () => filters.value.q,
  () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(runSearch, 300);
  }
);

watch(
  () => [
    filters.value.status,
    filters.value.country_code,
    filters.value.locale,
  ],
  runSearch
);
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="p-6">
    <div class="flex items-center gap-3 mb-4">
      <input
        v-model="filters.q"
        type="search"
        placeholder="Search photographer-directory and current campaign…"
        class="reset-base flex-1 min-w-0 h-10 px-3 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
      />
      <select
        v-model="filters.status"
        class="!w-44 !mb-0 flex-none h-10 text-sm bg-white border rounded border-n-weak"
      >
        <option v-for="s in STATUSES" :key="s.value" :value="s.value">
          {{ s.label }}
        </option>
      </select>
      <input
        v-model="filters.country_code"
        type="text"
        placeholder="Country"
        maxlength="2"
        list="photographer-countries"
        class="reset-base flex-none w-24 h-10 px-3 text-sm uppercase bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10"
      />
      <datalist id="photographer-countries">
        <option v-for="c in countryOptions" :key="c" :value="c" />
      </datalist>
      <input
        v-model="filters.locale"
        type="text"
        placeholder="Locale"
        maxlength="5"
        list="photographer-locales"
        class="reset-base flex-none w-24 h-10 px-3 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10"
      />
      <datalist id="photographer-locales">
        <option v-for="l in localeOptions" :key="l" :value="l" />
      </datalist>
      <a
        href="https://framky.com/pl-pl/dodaj-fotografa"
        target="_blank"
        rel="noopener noreferrer"
        class="flex-none whitespace-nowrap h-10 flex items-center px-4 text-sm font-medium text-white rounded bg-n-brand hover:opacity-90"
        title="Dodawanie fotografów odbywa się teraz w photographer-directory. Po zatwierdzeniu znajdziesz ich tutaj w wyszukiwaniu."
      >
        + Dodaj w directory ↗
      </a>
    </div>

    <div class="flex items-center gap-4 mb-3 text-xs text-n-slate-11">
      <span>
        In campaign: <strong>{{ profilesTotal }}</strong>
      </span>
      <span v-if="directoryTotal > 0">
        Directory matches: <strong>{{ directoryTotal }}</strong>
      </span>
      <span v-if="totalShown" class="ml-auto">
        Showing {{ totalShown }} row{{ totalShown === 1 ? '' : 's' }}
      </span>
    </div>

    <!-- Add-photographer panel (disabled under SSOT-in-directory) -->
    <div
      v-if="showAddForm"
      class="p-4 mb-4 bg-white border rounded border-n-amber-7 bg-n-amber-2/40"
    >
      <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
        Disabled — directory is the source of truth
      </h3>
      <p class="text-xs text-n-slate-11 mb-3">
        Pełne dodawanie fotografów odbywa się w photographer-directory UI. Po
        zatwierdzeniu rekordu tam, wyszukaj go tutaj i kliknij „Start campaign".
      </p>
      <button
        type="button"
        class="px-3 py-1.5 text-sm border rounded border-n-weak"
        @click="showAddForm = false"
      >
        OK
      </button>
      <form class="hidden" @submit.prevent="submitAdd">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Email *</span>
          <input
            v-model="addForm.email"
            type="email"
            required
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Business name</span>
          <input
            v-model="addForm.business_name"
            type="text"
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Owner name</span>
          <input
            v-model="addForm.owner_name"
            type="text"
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Website</span>
          <input
            v-model="addForm.website"
            type="url"
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Country (PL, DE…)</span>
          <input
            v-model="addForm.country_code"
            type="text"
            maxlength="2"
            class="reset-base px-2 py-1.5 bg-white uppercase border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Locale (pl, de, en…)</span>
          <input
            v-model="addForm.preferred_language"
            type="text"
            maxlength="5"
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex flex-col gap-1 col-span-2">
          <span class="text-xs text-n-slate-11">Instagram handle</span>
          <input
            v-model="addForm.instagram_handle"
            type="text"
            class="reset-base px-2 py-1.5 bg-white border rounded border-n-weak"
          />
        </label>
        <label class="flex items-center gap-2 col-span-2">
          <input v-model="addForm.enroll" type="checkbox" />
          <span class="text-xs text-n-slate-11">
            Enroll immediately in the photographer_partnership campaign (intro
            stage, due now)
          </span>
        </label>
        <div class="flex items-center justify-end gap-2 col-span-2">
          <button
            type="button"
            class="px-3 py-1.5 text-sm border rounded border-n-weak"
            :disabled="addSaving"
            @click="
              showAddForm = false;
              addForm = blankAddForm();
            "
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-3 py-1.5 text-sm font-medium text-white rounded bg-n-brand hover:opacity-90 disabled:opacity-60"
            :disabled="addSaving || !addForm.email"
          >
            {{ addSaving ? 'Saving…' : 'Create & enroll' }}
          </button>
        </div>
      </form>
    </div>

    <div
      v-if="importSummary"
      class="p-3 mb-3 text-xs rounded bg-n-teal-3 text-n-teal-11"
    >
      {{
        `Started campaign for ${importSummary.enrolled} (re-enrolled ${importSummary.re_enrolled}, already enrolled ${importSummary.already_enrolled}, skipped DNC ${importSummary.skipped_dnc}, failed ${importSummary.failed})`
      }}
    </div>

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
      v-else-if="rows.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No results. Type a name, email or Instagram handle to search the
      photographer-directory, or use <strong>+ Add photographer</strong>.
    </div>

    <table
      v-else
      class="w-full text-sm border rounded border-n-weak overflow-hidden"
    >
      <thead class="bg-n-slate-2 text-n-slate-11">
        <tr>
          <th class="px-3 py-2 font-medium text-left">Business</th>
          <th class="px-3 py-2 font-medium text-left">Owner</th>
          <th class="px-3 py-2 font-medium text-left">Email</th>
          <th class="px-3 py-2 font-medium text-left">Country</th>
          <th class="px-3 py-2 font-medium text-left">Locale</th>
          <th class="px-3 py-2 font-medium text-left">Status</th>
          <th class="px-3 py-2 font-medium text-left">Status since</th>
          <th class="px-3 py-2 font-medium text-right">Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.key"
          class="border-t border-n-weak hover:bg-n-slate-2/40"
          :class="[
            row.type === 'profile' ? 'cursor-pointer' : '',
            editingProfile &&
            row.profile &&
            editingProfile.id === row.profile.id
              ? 'bg-n-brand-3'
              : '',
          ]"
          @click="row.type === 'profile' && openEdit(row.profile)"
        >
          <td class="px-3 py-2 font-medium text-n-slate-12">
            <div class="flex items-center gap-2 flex-wrap">
              <span>{{ row.business_name || '—' }}</span>
              <a
                v-if="row.website"
                :href="websiteHref(row.website)"
                target="_blank"
                rel="noopener noreferrer"
                class="text-xs font-normal text-n-brand hover:underline"
                :title="row.website"
                @click.stop
              >
                {{ row.website }} ↗
              </a>
              <span
                v-if="row.type === 'directory'"
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-slate-3 text-n-slate-11"
                title="From photographer-directory, not yet in a campaign"
              >
                Directory
              </span>
              <span
                v-if="
                  row.profile &&
                  row.profile.marketing_consent_state === 'granted'
                "
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-teal-3 text-n-teal-11"
                title="Marketing consent: granted"
              >
                ✓ consent
              </span>
              <span
                v-else-if="
                  row.profile &&
                  row.profile.marketing_consent_state === 'declined'
                "
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-ruby-3 text-n-ruby-11"
                title="Marketing consent: refused"
              >
                ✕ consent
              </span>
              <span
                v-if="row.directory && row.directory.marketing_consent"
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-teal-3 text-n-teal-11"
                title="Marketing consent recorded in directory"
              >
                Marketing consent
              </span>
              <span
                v-if="row.directory && row.directory.in_directory_campaign"
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-amber-3 text-n-amber-11"
                title="Active onboarding CRM campaign — would double-contact"
              >
                In directory CRM
              </span>
              <span
                v-if="
                  row.directory &&
                  row.directory.email_validation_status &&
                  row.directory.email_validation_status.startsWith('invalid')
                "
                class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-ruby-3 text-n-ruby-11"
                :title="`Email bounced previously: ${row.directory.email_validation_status}`"
              >
                {{
                  row.directory.email_validation_status.replace(
                    'invalid_',
                    'Bounced: '
                  )
                }}
              </span>
            </div>
          </td>
          <td class="px-3 py-2 text-n-slate-11">{{ row.owner_name || '—' }}</td>
          <td class="px-3 py-2 text-n-slate-11">{{ row.email }}</td>
          <td class="px-3 py-2 uppercase text-n-slate-11">
            {{ row.country_code || '—' }}
          </td>
          <td class="px-3 py-2 text-n-slate-11">
            {{ row.preferred_language || '—' }}
          </td>
          <td class="px-3 py-2">
            <span
              v-if="row.type === 'profile'"
              class="px-2 py-0.5 text-xs font-medium rounded-full"
              :class="
                row.profile.partnership_status === 'signed_up'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : row.profile.partnership_status === 'do_not_contact'
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-slate-3 text-n-slate-11'
              "
            >
              {{ row.profile.partnership_status }}
            </span>
            <span v-else class="text-xs text-n-slate-11">—</span>
          </td>
          <td class="px-3 py-2 text-n-slate-11">
            <template v-if="row.type === 'profile'">
              {{ formatDate(row.profile.partnership_status_changed_at) }}
            </template>
            <template v-else>—</template>
          </td>
          <td class="px-3 py-2 text-right">
            <button
              v-if="
                row.type === 'profile' &&
                row.profile.partnership_status !== 'do_not_contact'
              "
              type="button"
              class="text-xs font-medium text-n-ruby-11 hover:underline disabled:opacity-50"
              :disabled="busyRowKey === row.key"
              @click.stop="optOut(row.profile)"
            >
              Opt out
            </button>
            <button
              v-else-if="row.type === 'directory'"
              type="button"
              class="text-xs font-medium text-n-brand hover:underline disabled:opacity-50"
              :disabled="busyRowKey === row.key"
              @click.stop="startCampaign(row)"
            >
              {{ busyRowKey === row.key ? 'Starting…' : 'Start campaign' }}
            </button>
          </td>
        </tr>
      </tbody>
    </table>

    <PhotographerEditSidebar
      :profile="editingProfile"
      :country-options="countryOptions"
      :locale-options="localeOptions"
      @close="closeEdit"
      @saved="onSaved"
    />
  </div>
</template>
