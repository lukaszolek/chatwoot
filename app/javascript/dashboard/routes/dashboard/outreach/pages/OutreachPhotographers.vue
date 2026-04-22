<script setup>
import { ref, onMounted, watch } from 'vue';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';

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
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="p-6">
    <div class="flex items-center gap-3 mb-4">
      <input
        v-model="filters.q"
        type="search"
        placeholder="Search email / business / owner…"
        class="flex-1 max-w-sm px-3 py-2 text-sm bg-white border rounded border-n-weak focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none"
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
        class="w-32 px-3 py-2 text-sm uppercase bg-white border rounded border-n-weak"
      />
      <input
        v-model="filters.locale"
        type="text"
        placeholder="Locale (pl…)"
        maxlength="5"
        class="w-32 px-3 py-2 text-sm bg-white border rounded border-n-weak"
      />
      <span class="ml-auto text-sm text-n-slate-11">{{ total }} total</span>
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
      v-else-if="profiles.length === 0"
      class="py-12 text-sm text-center text-n-slate-11"
    >
      No photographers match the current filters.
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
