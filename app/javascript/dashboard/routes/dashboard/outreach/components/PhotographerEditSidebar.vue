<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import OutreachThreadsPanel from './OutreachThreadsPanel.vue';
import PhotographerInfoCard from './PhotographerInfoCard.vue';

defineProps({
  profile: { type: Object, default: null },
  countryOptions: { type: Array, default: () => [] },
  localeOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();

const error = ref(null);
const errorHint = ref(null);

const closeSidebar = () => {
  store.dispatch('clearSelectedState');
  emit('close');
};

const onFieldSaved = data => {
  error.value = null;
  errorHint.value = null;
  emit('saved', data);
};

const onFieldError = ({ message, hint }) => {
  error.value = message;
  errorHint.value = hint;
};

const dismissError = () => {
  error.value = null;
  errorHint.value = null;
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <transition name="drawer">
    <aside
      v-if="profile"
      class="fixed top-0 right-0 bottom-0 z-50 max-w-[95vw] w-[960px] flex flex-col bg-white border-l border-n-weak shadow-2xl"
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

      <div
        v-if="error"
        class="flex items-start justify-between gap-2 px-4 py-2 text-sm bg-n-ruby-3 text-n-ruby-11"
      >
        <div>
          <div>{{ error }}</div>
          <div v-if="errorHint" class="mt-1 text-xs">{{ errorHint }}</div>
        </div>
        <button
          type="button"
          class="text-xs hover:underline shrink-0"
          @click="dismissError"
        >
          Zamknij
        </button>
      </div>

      <PhotographerInfoCard
        :profile="profile"
        :country-options="countryOptions"
        :locale-options="localeOptions"
        @field-saved="onFieldSaved"
        @field-error="onFieldError"
      />

      <OutreachThreadsPanel
        class="flex-1 min-h-0"
        :contact-id="profile.contact_id"
      />
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
