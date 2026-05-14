<script setup>
import { ref, computed, watch } from 'vue';
import OutreachPhotographersAPI from 'dashboard/api/outreachPhotographers';
import InlineEditableField from './InlineEditableField.vue';

const props = defineProps({
  profile: { type: Object, required: true },
  countryOptions: { type: Array, default: () => [] },
  localeOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['fieldSaved', 'fieldError']);

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

const profileLocale = p =>
  p?.native_language ||
  p?.directory_preferred_language ||
  p?.preferred_language ||
  '';

const localProfile = ref({
  ...props.profile,
  locale: profileLocale(props.profile),
});

watch(
  () => props.profile?.id,
  () => {
    localProfile.value = {
      ...props.profile,
      locale: profileLocale(props.profile),
    };
  }
);

const directoryUrl = computed(() => {
  if (!localProfile.value?.external_id) return null;
  return `https://framky.com/pl-pl/fotograf/${localProfile.value.external_id}`;
});

const websiteHref = computed(() => {
  const w = localProfile.value.website;
  if (!w) return null;
  return /^https?:\/\//i.test(w) ? w : `https://${w}`;
});

const instagramHref = computed(() => {
  const h = localProfile.value.instagram_handle;
  if (!h) return null;
  const handle = h.replace(/^@/, '').trim();
  if (!handle) return null;
  return `https://instagram.com/${handle}`;
});

const buildPayload = (field, value) => {
  if (field === 'locale') {
    return { native_language: value, preferred_language: value };
  }
  return { [field]: value };
};

const saveField = async (field, value) => {
  const payload = buildPayload(field, value);
  const { data } = await OutreachPhotographersAPI.update(
    localProfile.value.id,
    payload
  );
  localProfile.value = { ...data, locale: profileLocale(data) };
  emit('fieldSaved', data);
  return data;
};

const onError = err => emit('fieldError', err);

// --- Marketing consent flag (cycle through unknown → granted → declined) ---
const consentSaving = ref(false);
const consentOpen = ref(false);

const currentConsent = computed(
  () =>
    CONSENT_OPTIONS.find(
      o => o.value === localProfile.value.marketing_consent_state
    ) || CONSENT_OPTIONS[0]
);

const consentDotClass = computed(() => {
  switch (currentConsent.value.tone) {
    case 'teal':
      return 'bg-n-teal-9';
    case 'ruby':
      return 'bg-n-ruby-9';
    default:
      return 'bg-n-slate-6';
  }
});

const setConsent = async value => {
  consentOpen.value = false;
  if (
    consentSaving.value ||
    localProfile.value.marketing_consent_state === value
  )
    return;
  consentSaving.value = true;
  try {
    await saveField('marketing_consent_state', value);
  } catch (e) {
    onError({
      message:
        e?.response?.data?.message || e?.response?.data?.error || e?.message,
      hint: e?.response?.data?.hint || null,
    });
  } finally {
    consentSaving.value = false;
  }
};

// --- Copy email to clipboard ---
const emailCopied = ref(false);
const copyEmail = async () => {
  const addr = localProfile.value.email;
  if (!addr) return;
  try {
    await navigator.clipboard.writeText(addr);
    emailCopied.value = true;
    setTimeout(() => {
      emailCopied.value = false;
    }, 1500);
  } catch {
    onError({ message: 'Nie udało się skopiować adresu', hint: null });
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <section
    class="flex items-start justify-between gap-3 px-4 py-2 border-b border-n-weak"
  >
    <div class="flex flex-col min-w-0 flex-1 gap-0.5">
      <div class="flex items-center gap-2 flex-wrap min-w-0">
        <InlineEditableField
          variant="heading"
          type="text"
          display-class="text-lg font-semibold leading-tight"
          placeholder="Imię i nazwisko"
          :model-value="localProfile.owner_name"
          :save-fn="value => saveField('owner_name', value)"
          @error="onError"
        />
        <InlineEditableField
          variant="tag"
          type="text"
          :model-value="localProfile.country_code"
          :save-fn="value => saveField('country_code', value)"
          :maxlength="2"
          datalist-id="photographer-countries"
          placeholder="–"
          uppercase
          @error="onError"
        />
        <InlineEditableField
          variant="tag"
          type="text"
          :model-value="localProfile.locale"
          :save-fn="value => saveField('locale', value)"
          :maxlength="5"
          datalist-id="photographer-locales"
          placeholder="–"
          @error="onError"
        />
        <InlineEditableField
          variant="tag"
          type="select"
          :model-value="localProfile.partnership_status"
          :options="STATUS_OPTIONS"
          :save-fn="value => saveField('partnership_status', value)"
          placeholder="status"
          @error="onError"
        />
      </div>
      <InlineEditableField
        variant="heading"
        type="text"
        display-class="text-sm text-n-slate-11"
        placeholder="Nazwa biznesu"
        :model-value="localProfile.business_name"
        :save-fn="value => saveField('business_name', value)"
        @error="onError"
      />
      <div
        v-if="!localProfile.directory_linked"
        class="text-xs text-n-ruby-11 mt-0.5"
      >
        ⚠️ Directory niedostępne — pola PII nie zostały załadowane.
      </div>
    </div>

    <div class="flex items-center gap-1 shrink-0">
      <a
        v-if="websiteHref"
        :href="websiteHref"
        target="_blank"
        rel="noopener noreferrer"
        title="Strona www"
        class="size-7 inline-flex items-center justify-center rounded hover:bg-n-alpha-1 text-n-slate-11"
      >
        <span class="i-lucide-globe size-4" />
      </a>
      <a
        v-if="instagramHref"
        :href="instagramHref"
        target="_blank"
        rel="noopener noreferrer"
        :title="`@${localProfile.instagram_handle}`"
        class="size-7 inline-flex items-center justify-center rounded hover:bg-n-alpha-1 text-n-slate-11"
      >
        <span class="i-lucide-instagram size-4" />
      </a>

      <button
        v-if="localProfile.email"
        type="button"
        class="size-7 inline-flex items-center justify-center rounded hover:bg-n-alpha-1 text-n-slate-11 relative"
        :title="emailCopied ? 'Skopiowano!' : `Kopiuj: ${localProfile.email}`"
        @click="copyEmail"
      >
        <span
          :class="
            emailCopied
              ? 'i-lucide-check size-4 text-n-teal-11'
              : 'i-lucide-mail size-4'
          "
        />
      </button>

      <div class="relative">
        <button
          type="button"
          class="size-7 inline-flex items-center justify-center rounded hover:bg-n-alpha-1 disabled:opacity-60"
          :title="`Marketing consent: ${currentConsent.label}`"
          :disabled="consentSaving"
          @click="consentOpen = !consentOpen"
        >
          <span
            class="size-3 rounded-full border border-n-weak"
            :class="consentDotClass"
          />
        </button>
        <div
          v-if="consentOpen"
          class="absolute right-0 top-full mt-1 z-20 flex flex-col bg-white border border-n-weak rounded shadow-lg py-1 min-w-[160px]"
          @mouseleave="consentOpen = false"
        >
          <button
            v-for="opt in CONSENT_OPTIONS"
            :key="opt.value"
            type="button"
            class="flex items-center gap-2 px-2 py-1.5 text-xs text-left hover:bg-n-alpha-1"
            :class="{
              'bg-n-alpha-1':
                localProfile.marketing_consent_state === opt.value,
            }"
            @click="setConsent(opt.value)"
          >
            <span
              class="size-2.5 rounded-full"
              :class="{
                'bg-n-slate-6': opt.tone === 'slate',
                'bg-n-teal-9': opt.tone === 'teal',
                'bg-n-ruby-9': opt.tone === 'ruby',
              }"
            />
            {{ opt.label }}
          </button>
        </div>
      </div>

      <a
        v-if="directoryUrl"
        :href="directoryUrl"
        target="_blank"
        rel="noopener noreferrer"
        title="Otwórz w directory"
        class="size-7 inline-flex items-center justify-center rounded hover:bg-n-alpha-1 text-n-brand"
      >
        <span class="i-lucide-external-link size-4" />
      </a>
    </div>

    <datalist id="photographer-countries">
      <option v-for="c in countryOptions" :key="c" :value="c" />
    </datalist>
    <datalist id="photographer-locales">
      <option v-for="l in localeOptions" :key="l" :value="l" />
    </datalist>
  </section>
</template>
