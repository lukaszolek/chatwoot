<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import OutreachDirectoryAPI from 'dashboard/api/outreachDirectory';

const profiles = ref([]);
const total = ref(0);
const loading = ref(false);
const error = ref(null);
const page = ref(1);

const filters = ref({ q: '', status: '', country_code: '', locale: '' });

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

const fetchPage = async () => {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await OutreachPhotographersAPI.get(
      page.value,
      filters.value
    );
    profiles.value = data.data || [];
    total.value = data.meta?.total || 0;
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    loading.value = false;
  }
};

const optOut = async profile => {
  if (!window.confirm(`Opt ${profile.email} out of outreach?`)) return;
  try {
    await OutreachPhotographersAPI.optOut(profile.id);
    await fetchPage();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
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
    await fetchPage();
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.data?.message || e.message;
  } finally {
    addSaving.value = false;
  }
};

// ---------- Import from directory ----------
const showDirectory = ref(false);
const directoryLoading = ref(false);
const directoryResults = ref([]);
const directoryTotal = ref(0);
const directoryPage = ref(1);
const directoryFilters = ref({ q: '', country_code: '', locale: '' });
const directorySelected = ref(new Set());
const importBusy = ref(false);
const importSummary = ref(null);

const runDirectorySearch = async () => {
  directoryLoading.value = true;
  error.value = null;
  try {
    const { data } = await OutreachDirectoryAPI.search(
      directoryPage.value,
      directoryFilters.value
    );
    directoryResults.value = data.data || [];
    directoryTotal.value = data.meta?.total || 0;
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    directoryLoading.value = false;
  }
};

const openDirectory = () => {
  showDirectory.value = true;
  directorySelected.value = new Set();
  importSummary.value = null;
  runDirectorySearch();
};

const toggleSelect = id => {
  const next = new Set(directorySelected.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  directorySelected.value = next;
};

const selectAllVisible = () => {
  const next = new Set(directorySelected.value);
  directoryResults.value.forEach(r => {
    if (!r.already_enrolled) next.add(r.id);
  });
  directorySelected.value = next;
};

const clearSelection = () => {
  directorySelected.value = new Set();
};

const importableVisible = computed(() =>
  directoryResults.value.filter(r => !r.already_enrolled)
);
const allVisibleSelected = computed(
  () =>
    importableVisible.value.length > 0 &&
    importableVisible.value.every(r => directorySelected.value.has(r.id))
);
const someVisibleSelected = computed(() =>
  importableVisible.value.some(r => directorySelected.value.has(r.id))
);
const toggleSelectAllVisible = () => {
  if (allVisibleSelected.value) {
    const next = new Set(directorySelected.value);
    importableVisible.value.forEach(r => next.delete(r.id));
    directorySelected.value = next;
  } else {
    selectAllVisible();
  }
};

const runImport = async (ids = null) => {
  const toImport = ids || Array.from(directorySelected.value);
  if (toImport.length === 0) return;
  importBusy.value = true;
  importSummary.value = null;
  error.value = null;
  try {
    const { data } = await OutreachDirectoryAPI.import(toImport);
    importSummary.value = data.result;
    await Promise.all([runDirectorySearch(), fetchPage()]);
    directorySelected.value = new Set();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    importBusy.value = false;
  }
};

// ---------- Reactivity ----------
const formatDate = ts => (ts ? new Date(ts * 1000).toLocaleString() : '—');

onMounted(fetchPage);

let searchTimer = null;
watch(
  () => filters.value.q,
  () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      page.value = 1;
      fetchPage();
    }, 300);
  }
);

watch(
  () => [
    filters.value.status,
    filters.value.country_code,
    filters.value.locale,
  ],
  () => {
    page.value = 1;
    fetchPage();
  }
);

let dirSearchTimer = null;
watch(
  () => directoryFilters.value.q,
  () => {
    clearTimeout(dirSearchTimer);
    dirSearchTimer = setTimeout(() => {
      directoryPage.value = 1;
      runDirectorySearch();
    }, 300);
  }
);
watch(
  () => [directoryFilters.value.country_code, directoryFilters.value.locale],
  () => {
    directoryPage.value = 1;
    runDirectorySearch();
  }
);
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="p-6">
    <div class="flex items-center gap-3 mb-4">
      <input
        v-model="filters.q"
        type="search"
        placeholder="Search email / business / owner…"
        class="reset-base flex-none w-80 px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
      />
      <select
        v-model="filters.status"
        class="px-3 py-2 text-sm bg-white border rounded border-n-weak"
      >
        <option v-for="s in STATUSES" :key="s.value" :value="s.value">
          {{ s.label }}
        </option>
      </select>
      <input
        v-model="filters.country_code"
        type="text"
        placeholder="Country (PL…)"
        maxlength="2"
        class="reset-base flex-none w-36 px-3 py-2 text-sm uppercase bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10"
      />
      <input
        v-model="filters.locale"
        type="text"
        placeholder="Locale (pl…)"
        maxlength="5"
        class="reset-base flex-none w-36 px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10"
      />
      <span class="ml-auto text-sm text-n-slate-11">{{ total }} total</span>
      <button
        type="button"
        class="px-3 py-2 text-sm font-medium border rounded border-n-weak hover:bg-n-slate-2"
        @click="openDirectory"
      >
        Import from directory
      </button>
      <button
        type="button"
        class="px-3 py-2 text-sm font-medium text-white rounded bg-n-brand hover:opacity-90"
        @click="showAddForm = true"
      >
        + Add photographer
      </button>
    </div>

    <!-- Add-photographer panel -->
    <div
      v-if="showAddForm"
      class="p-4 mb-4 bg-white border rounded border-n-weak"
    >
      <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
        Add a photographer and enroll in the partnership campaign
      </h3>
      <form class="grid grid-cols-2 gap-3 text-sm" @submit.prevent="submitAdd">
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

    <!-- Directory import panel -->
    <div
      v-if="showDirectory"
      class="p-4 mb-4 bg-white border rounded border-n-weak"
    >
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-n-slate-12">
          Import from photographer-directory
        </h3>
        <button
          type="button"
          class="text-xs text-n-slate-11 hover:underline"
          @click="showDirectory = false"
        >
          Close
        </button>
      </div>

      <div class="flex items-center gap-3 mb-3">
        <input
          v-model="directoryFilters.q"
          type="search"
          placeholder="Search name / email / Instagram handle…"
          class="reset-base flex-none w-96 px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
        />
        <input
          v-model="directoryFilters.country_code"
          type="text"
          maxlength="2"
          placeholder="Country (de…)"
          class="reset-base flex-none w-36 px-3 py-2 text-sm uppercase bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
        />
        <input
          v-model="directoryFilters.locale"
          type="text"
          maxlength="5"
          placeholder="Locale (de…)"
          class="reset-base flex-none w-36 px-3 py-2 text-sm bg-white border rounded border-n-weak text-n-slate-12 placeholder-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
        />
        <span class="ml-auto text-xs text-n-slate-11">
          {{ directoryTotal }} available · {{ directorySelected.size }} selected
        </span>
      </div>

      <div
        v-if="importSummary"
        class="p-3 mb-3 text-xs rounded bg-n-teal-3 text-n-teal-11"
      >
        Imported: <strong>{{ importSummary.enrolled }}</strong> · re-enrolled:
        <strong>{{ importSummary.re_enrolled }}</strong> · already enrolled:
        <strong>{{ importSummary.already_enrolled }}</strong> · skipped DNC:
        <strong>{{ importSummary.skipped_dnc }}</strong> · failed:
        <strong>{{ importSummary.failed }}</strong>
      </div>

      <div
        v-if="directoryLoading"
        class="py-8 text-sm text-center text-n-slate-11"
      >
        Searching directory…
      </div>

      <div
        v-else-if="directoryResults.length === 0"
        class="py-8 text-sm text-center text-n-slate-11"
      >
        No directory rows match (or all current matches are already excluded).
      </div>

      <table
        v-else
        class="w-full text-sm border rounded border-n-weak overflow-hidden"
      >
        <thead class="bg-n-slate-2 text-n-slate-11">
          <tr>
            <th class="px-3 py-2 w-8">
              <input
                type="checkbox"
                :checked="allVisibleSelected"
                :indeterminate.prop="someVisibleSelected && !allVisibleSelected"
                :title="
                  allVisibleSelected
                    ? 'Clear selection on this page'
                    : 'Select all importable rows on this page'
                "
                @change="toggleSelectAllVisible"
              />
            </th>
            <th class="px-3 py-2 text-left font-medium">Business</th>
            <th class="px-3 py-2 text-left font-medium">Owner</th>
            <th class="px-3 py-2 text-left font-medium">Email</th>
            <th class="px-3 py-2 text-left font-medium">Country</th>
            <th class="px-3 py-2 text-left font-medium">Locale</th>
            <th class="px-3 py-2 text-right font-medium">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="r in directoryResults"
            :key="r.id"
            class="border-t border-n-weak hover:bg-n-slate-2/40"
            :class="r.already_enrolled ? 'opacity-60' : ''"
          >
            <td class="px-3 py-2">
              <input
                type="checkbox"
                :checked="directorySelected.has(r.id)"
                :disabled="r.already_enrolled"
                @change="toggleSelect(r.id)"
              />
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              <div class="flex items-center gap-2">
                <span>{{ r.business_name || '—' }}</span>
                <span
                  v-if="r.already_enrolled"
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-teal-3 text-n-teal-11"
                  title="Already in chatwoot outreach"
                >
                  Enrolled
                </span>
                <span
                  v-if="r.in_directory_campaign"
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-amber-3 text-n-amber-11"
                  title="Active onboarding CRM campaign — would double-contact"
                >
                  In directory CRM
                </span>
                <span
                  v-if="r.marketing_consent"
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-teal-3 text-n-teal-11"
                  title="Marketing consent recorded in directory"
                >
                  Marketing consent
                </span>
                <span
                  v-if="
                    r.email_validation_status &&
                    r.email_validation_status.startsWith('invalid')
                  "
                  class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-ruby-3 text-n-ruby-11"
                  :title="`Email bounced previously: ${r.email_validation_status}`"
                >
                  {{
                    r.email_validation_status.replace('invalid_', 'Bounced: ')
                  }}
                </span>
              </div>
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ r.owner_name || '—' }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ r.email }}</td>
            <td class="px-3 py-2 uppercase text-n-slate-11">
              {{ r.country_code || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ r.preferred_language || '—' }}
            </td>
            <td class="px-3 py-2 text-right">
              <button
                v-if="!r.already_enrolled"
                type="button"
                class="text-xs font-medium text-n-brand hover:underline disabled:opacity-50"
                :disabled="importBusy"
                @click="runImport([r.id])"
              >
                Import
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <div class="flex items-center justify-between mt-4 text-sm">
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="px-3 py-1.5 text-xs border rounded border-n-weak"
            :disabled="importBusy"
            @click="selectAllVisible"
          >
            Select all visible
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs border rounded border-n-weak"
            :disabled="importBusy || directorySelected.size === 0"
            @click="clearSelection"
          >
            Clear
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium text-white rounded bg-n-brand hover:opacity-90 disabled:opacity-60"
            :disabled="importBusy || directorySelected.size === 0"
            @click="runImport()"
          >
            {{
              importBusy
                ? 'Importing…'
                : `Import ${directorySelected.size} selected`
            }}
          </button>
        </div>
        <div
          v-if="directoryTotal > directoryResults.length"
          class="flex items-center gap-2"
        >
          <button
            type="button"
            :disabled="directoryPage === 1 || directoryLoading"
            class="px-3 py-1.5 text-xs border rounded border-n-weak disabled:opacity-50"
            @click="
              directoryPage -= 1;
              runDirectorySearch();
            "
          >
            Previous
          </button>
          <span class="text-xs text-n-slate-11">Page {{ directoryPage }}</span>
          <button
            type="button"
            class="px-3 py-1.5 text-xs border rounded border-n-weak"
            :disabled="directoryLoading"
            @click="
              directoryPage += 1;
              runDirectorySearch();
            "
          >
            Next
          </button>
        </div>
      </div>
    </div>

    <!-- Current enrolled list -->
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
      v-else-if="profiles.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No photographers match the current filters. Use
      <strong>Import from directory</strong> or
      <strong>+ Add photographer</strong> above.
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
          v-for="profile in profiles"
          :key="profile.id"
          class="border-t border-n-weak hover:bg-n-slate-2/40"
        >
          <td class="px-3 py-2 font-medium text-n-slate-12">
            {{ profile.business_name || '—' }}
          </td>
          <td class="px-3 py-2 text-n-slate-11">
            {{ profile.owner_name || '—' }}
          </td>
          <td class="px-3 py-2 text-n-slate-11">{{ profile.email }}</td>
          <td class="px-3 py-2 uppercase text-n-slate-11">
            {{ profile.country_code || '—' }}
          </td>
          <td class="px-3 py-2 text-n-slate-11">
            {{ profile.preferred_language || '—' }}
          </td>
          <td class="px-3 py-2">
            <span
              class="px-2 py-0.5 text-xs font-medium rounded-full"
              :class="
                profile.partnership_status === 'signed_up'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : profile.partnership_status === 'do_not_contact'
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-slate-3 text-n-slate-11'
              "
            >
              {{ profile.partnership_status }}
            </span>
          </td>
          <td class="px-3 py-2 text-n-slate-11">
            {{ formatDate(profile.partnership_status_changed_at) }}
          </td>
          <td class="px-3 py-2 text-right">
            <button
              v-if="profile.partnership_status !== 'do_not_contact'"
              type="button"
              class="text-xs font-medium text-n-ruby-11 hover:underline"
              @click="optOut(profile)"
            >
              Opt out
            </button>
          </td>
        </tr>
      </tbody>
    </table>

    <div
      v-if="total > profiles.length"
      class="flex items-center justify-between mt-4 text-sm"
    >
      <button
        type="button"
        :disabled="page === 1"
        class="px-3 py-1.5 border rounded border-n-weak disabled:opacity-50"
        @click="
          page -= 1;
          fetchPage();
        "
      >
        Previous
      </button>
      <span class="text-n-slate-11">Page {{ page }}</span>
      <button
        type="button"
        class="px-3 py-1.5 border rounded border-n-weak"
        @click="
          page += 1;
          fetchPage();
        "
      >
        Next
      </button>
    </div>
  </div>
</template>
