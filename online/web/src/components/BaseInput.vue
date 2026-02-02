<template>
  <input
    class="input"
    :value="modelValue"
    :placeholder="placeholder"
    type="search"
    autocomplete="off"
    @input="onInput"
  />
</template>

<script setup lang="ts">
const props = defineProps<{
  modelValue: string;
  placeholder?: string;
}>();

const emit = defineEmits<{ (e: 'update:modelValue', v: string): void }>();

function onInput(e: Event): void {
  const el = e.target as HTMLInputElement | null;
  emit('update:modelValue', el?.value ?? '');
}
</script>

<style scoped>
.input {
  width: 100%;
  border: 0.0625rem solid var(--border);
  border-radius: 0.6rem;
  padding: 0.65rem 0.75rem;
  background: var(--bg);
  color: var(--fg);
  font: inherit;
  outline: none;
}

.input:focus {
  border-color: color-mix(in srgb, var(--accent) 60%, var(--border) 40%);
}
</style>

