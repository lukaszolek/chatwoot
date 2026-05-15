<script setup>
import { ref, computed, nextTick, watch } from 'vue';

const props = defineProps({
  modelValue: { type: [String, Number, null], default: '' },
  type: {
    type: String,
    default: 'text',
    validator: v =>
      ['text', 'email', 'url', 'tel', 'select', 'textarea'].includes(v),
  },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '—' },
  options: { type: Array, default: () => [] }, // for select / datalist values
  optionLabels: { type: Object, default: () => ({}) }, // optional label map for select
  maxlength: { type: [Number, String], default: null },
  uppercase: { type: Boolean, default: false },
  datalistId: { type: String, default: null },
  disabled: { type: Boolean, default: false },
  // Visual variants: 'default' = label + cell input, 'tag' = pill chip,
  // 'heading' = unstyled large display (caller passes displayClass).
  variant: {
    type: String,
    default: 'default',
    validator: v => ['default', 'tag', 'heading'].includes(v),
  },
  // Extra classes applied to the read-only button (heading sizing etc.).
  displayClass: { type: String, default: '' },
  // async (value) => updatedProfile  — caller does the API call
  saveFn: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue', 'saved', 'error']);

const editing = ref(false);
const saving = ref(false);
const draft = ref('');
const errored = ref(false);
const justSaved = ref(false);
const inputRef = ref(null);

const displayValue = computed(() => {
  const v = props.modelValue;
  if (v === null || v === undefined || v === '') return null;
  if (props.type === 'select' && props.optionLabels[v]) {
    return props.optionLabels[v];
  }
  return String(v);
});

const startEdit = async () => {
  if (props.disabled || editing.value) return;
  draft.value = props.modelValue == null ? '' : String(props.modelValue);
  editing.value = true;
  errored.value = false;
  await nextTick();
  const el = inputRef.value;
  if (!el) return;
  el.focus();
  if (typeof el.select === 'function' && props.type !== 'textarea') {
    el.select();
  }
};

const cancelEdit = () => {
  editing.value = false;
  draft.value = '';
  errored.value = false;
};

const commit = async () => {
  if (saving.value) return;
  const before = props.modelValue == null ? '' : String(props.modelValue);
  let after = draft.value == null ? '' : String(draft.value);
  if (props.uppercase) after = after.toUpperCase();
  if (before === after) {
    editing.value = false;
    return;
  }
  saving.value = true;
  errored.value = false;
  try {
    const result = await props.saveFn(after);
    emit('update:modelValue', after);
    emit('saved', result);
    editing.value = false;
    justSaved.value = true;
    setTimeout(() => {
      justSaved.value = false;
    }, 1500);
  } catch (e) {
    const body = e?.response?.data || {};
    errored.value = true;
    emit('error', {
      message: body.message || body.error || e?.message || 'Save failed',
      hint: body.hint || null,
    });
  } finally {
    saving.value = false;
  }
};

// Selects + radio-style fields: caller flips modelValue externally then calls
// `commitImmediate(value)`. For native <select> bound below we call commit on
// @change after updating draft.
const onSelectChange = async event => {
  draft.value = event.target.value;
  await commit();
};

watch(
  () => props.modelValue,
  () => {
    // Parent overwrote value (e.g. profile reset on new photographer) —
    // exit edit mode to avoid stale draft.
    if (!editing.value) errored.value = false;
  }
);

const onKeydown = e => {
  if (e.key === 'Escape') {
    e.preventDefault();
    cancelEdit();
    return;
  }
  if (e.key === 'Enter' && props.type !== 'textarea') {
    e.preventDefault();
    commit();
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div
    class="min-w-0"
    :class="
      variant === 'default'
        ? 'flex flex-col gap-1'
        : 'inline-flex items-center gap-1'
    "
  >
    <div v-if="label && variant === 'default'" class="flex items-center gap-2">
      <span class="text-[11px] uppercase tracking-wide text-n-slate-11">
        {{ label }}
      </span>
      <span v-if="saving" class="text-[10px] text-n-slate-10">zapisuję…</span>
      <span v-else-if="justSaved" class="text-[10px] text-n-teal-11">✓</span>
      <span v-else-if="errored" class="text-[10px] text-n-ruby-11">błąd</span>
    </div>

    <template v-if="!editing">
      <button
        type="button"
        class="reset-base text-left cursor-text"
        :class="[
          variant === 'tag'
            ? 'inline-flex items-center px-1.5 py-0.5 text-[11px] font-medium rounded bg-n-slate-3 text-n-slate-11 border border-n-weak hover:border-n-slate-7 leading-none uppercase tracking-wide'
            : variant === 'heading'
              ? 'text-n-slate-12 px-1 -mx-1 rounded hover:bg-n-alpha-1 truncate'
              : 'text-sm text-n-slate-12 px-2 py-1 -mx-2 rounded hover:bg-n-alpha-1 truncate',
          {
            'text-n-slate-10 italic': displayValue == null,
            'border border-n-ruby-9': errored,
            uppercase: uppercase && variant !== 'tag',
            'opacity-60': saving,
          },
          displayClass,
        ]"
        :title="saving ? 'zapisuję…' : errored ? 'błąd zapisu' : null"
        :disabled="disabled"
        @click="startEdit"
      >
        {{ displayValue == null ? placeholder : displayValue }}
      </button>
    </template>

    <template v-else>
      <textarea
        v-if="type === 'textarea'"
        ref="inputRef"
        v-model="draft"
        rows="3"
        class="reset-base w-full !mb-0 px-2 py-1.5 text-sm bg-white border rounded"
        :class="errored ? 'border-n-ruby-9' : 'border-n-weak'"
        :maxlength="maxlength || undefined"
        :placeholder="placeholder"
        @blur="commit"
        @keydown="onKeydown"
      />
      <select
        v-else-if="type === 'select'"
        ref="inputRef"
        v-model="draft"
        class="reset-base px-2 text-sm bg-white border rounded"
        :class="[
          variant === 'tag' ? 'h-6 text-[11px]' : 'w-full h-8',
          errored ? 'border-n-ruby-9' : 'border-n-weak',
        ]"
        @change="onSelectChange"
        @blur="cancelEdit"
        @keydown.esc.prevent="cancelEdit"
      >
        <option v-for="opt in options" :key="opt" :value="opt">
          {{ optionLabels[opt] || opt }}
        </option>
      </select>
      <input
        v-else
        ref="inputRef"
        v-model="draft"
        :type="type"
        class="reset-base px-2 text-sm bg-white border rounded"
        :class="[
          variant === 'tag' ? 'h-6 text-[11px]' : 'w-full h-8',
          variant === 'heading' ? 'w-full' : '',
          errored ? 'border-n-ruby-9' : 'border-n-weak',
          uppercase ? 'uppercase' : '',
          displayClass,
        ]"
        :style="
          variant === 'tag'
            ? `width: ${Math.max((draft || '').length, 2) + 2}ch`
            : ''
        "
        :maxlength="maxlength || undefined"
        :list="datalistId || undefined"
        :placeholder="placeholder"
        @blur="commit"
        @keydown="onKeydown"
      />
    </template>
  </div>
</template>
