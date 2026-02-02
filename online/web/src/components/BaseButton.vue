<template>
  <button class="btn" :class="variantClass" :disabled="disabled" type="button">
    <slot />
  </button>
</template>

<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  variant?: 'default' | 'primary';
  disabled?: boolean;
}>();

const variantClass = computed(() => (props.variant === 'primary' ? 'btn--primary' : 'btn--default'));
</script>

<style scoped>
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  padding: 0.45rem 0.7rem;
  border: 0.0625rem solid var(--border);
  border-radius: 0.6rem;
  background: var(--bg);
  color: var(--fg);
  font: inherit;
  cursor: pointer;
  user-select: none;
}

.btn:hover {
  background: color-mix(in srgb, var(--bg) 92%, var(--fg) 8%);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn--primary {
  border-color: color-mix(in srgb, var(--accent) 70%, var(--border) 30%);
  color: var(--accent);
}
</style>

