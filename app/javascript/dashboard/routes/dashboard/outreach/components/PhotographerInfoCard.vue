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

// Local snapshot so per-field optimistic updates don't get clobbered while
// the parent list is mid-refresh. We re-hydrate only when the photographer
// id changes (operator opens a different row).
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

// `locale` is the directory's native_language + preferred_language. Keep
// the mapping symmetric with the original piiChanges() so a single edit
// updates both columns.
const buildPayload = (field, value) => {
  if (field === 'locale') {
    return { native_language: value, preferred_language: value };
  }
  return { [field]: value };
};

const consentSaving = ref(false);

const saveField = async (field, value) => {
  const payload = buildPayload(field, value);
  const { data } = await OutreachPhotographersAPI.update(
    localProfile.value.id,
    payload
  );
  // Merge the canonical row back in (keep `locale` derived field fresh).
  localProfile.value = { ...data, locale: profileLocale(data) };
  emit('fieldSaved', data);
  return data;
};

const onError = err => emit('fieldError', err);

const setConsent = async value => {
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
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <section class="flex flex-col gap-3 px-4 py-3 border-b border-n-weak">
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

    <div v-if="!localProfile.directory_linked" class="text-xs text-n-ruby-11">
      ⚠️ Directory niedostępne — pola PII nie zostały załadowane. Sprawdź VPN /
      secondary DB.
    </div>

    <div class="grid grid-cols-2 gap-x-4 gap-y-2">
      <InlineEditableField
        label="Business name"
        type="text"
        :model-value="localProfile.business_name"
        :save-fn="value => saveField('business_name', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Owner name"
        type="text"
        :model-value="localProfile.owner_name"
        :save-fn="value => saveField('owner_name', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Email"
        type="email"
        :model-value="localProfile.email"
        :save-fn="value => saveField('email', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Phone"
        type="tel"
        :model-value="localProfile.phone"
        :save-fn="value => saveField('phone', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Website"
        type="url"
        :model-value="localProfile.website"
        :save-fn="value => saveField('website', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Instagram handle"
        type="text"
        :model-value="localProfile.instagram_handle"
        :save-fn="value => saveField('instagram_handle', value)"
        @error="onError"
      />
      <InlineEditableField
        label="Country (2-letter)"
        type="text"
        :model-value="localProfile.country_code"
        :save-fn="value => saveField('country_code', value)"
        :maxlength="2"
        datalist-id="photographer-countries"
        uppercase
        @error="onError"
      />
      <InlineEditableField
        label="Locale"
        type="text"
        :model-value="localProfile.locale"
        :save-fn="value => saveField('locale', value)"
        :maxlength="5"
        datalist-id="photographer-locales"
        @error="onError"
      />
    </div>
    <datalist id="photographer-countries">
      <option v-for="c in countryOptions" :key="c" :value="c" />
    </datalist>
    <datalist id="photographer-locales">
      <option v-for="l in localeOptions" :key="l" :value="l" />
    </datalist>

    <div
      class="flex flex-wrap items-end gap-x-6 gap-y-3 pt-3 border-t border-n-weak"
    >
      <fieldset class="flex flex-col gap-1">
        <legend class="text-[11px] uppercase tracking-wide text-n-slate-11">
          Marketing consent
        </legend>
        <div class="flex items-center gap-1">
          <button
            v-for="opt in CONSENT_OPTIONS"
            :key="opt.value"
            type="button"
            class="px-2 py-0.5 text-xs font-medium rounded-full border transition-colors disabled:opacity-60"
            :class="
              localProfile.marketing_consent_state === opt.value
                ? {
                    'bg-n-teal-3 text-n-teal-11 border-n-teal-7':
                      opt.tone === 'teal',
                    'bg-n-ruby-3 text-n-ruby-11 border-n-ruby-7':
                      opt.tone === 'ruby',
                    'bg-n-slate-3 text-n-slate-11 border-n-slate-7':
                      opt.tone === 'slate',
                  }
                : 'bg-white text-n-slate-11 border-n-weak hover:border-n-slate-7'
            "
            :disabled="consentSaving"
            @click="setConsent(opt.value)"
          >
            {{ opt.label }}
          </button>
        </div>
      </fieldset>

      <div class="flex-1 min-w-[220px]">
        <InlineEditableField
          label="Partnership status"
          type="select"
          :model-value="localProfile.partnership_status"
          :options="STATUS_OPTIONS"
          :save-fn="value => saveField('partnership_status', value)"
          @error="onError"
        />
      </div>
    </div>

    <InlineEditableField
      label="Notes (operator-only)"
      type="textarea"
      :model-value="localProfile.notes"
      :save-fn="value => saveField('notes', value)"
      @error="onError"
    />
  </section>
</template>
