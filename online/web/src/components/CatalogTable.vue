<template>
  <div class="tableWrap">
    <table class="table">
      <thead>
        <tr>
          <th>{{ t(uiLang, '文件', 'File') }}</th>
          <th class="colSmall">{{ t(uiLang, '语言', 'Lang') }}</th>
          <th class="colSmall">{{ t(uiLang, '大小', 'Size') }}</th>
          <th class="colSmall">{{ t(uiLang, '修改时间', 'Updated') }}</th>
          <th class="colSmall">{{ t(uiLang, '操作', 'Actions') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="it in items" :key="it.id + ':' + it.relPath">
          <td class="path">
            <div class="docRow">
              <div class="avatar" aria-hidden="true">
                <img
                  v-if="it.icon"
                  class="avatarImg"
                  :src="it.icon"
                  alt=""
                  loading="lazy"
                  decoding="async"
                />
                <div v-else class="avatarFallback">{{ avatarText(it.name || it.id) }}</div>
              </div>
              <div class="docText">
                <a :href="it.mdUrl" target="_blank" rel="noreferrer">{{ it.relPath }}</a>
                <div class="name">
                  <span class="nameMain">{{ it.name }}</span>
                  <span v-if="it.title && it.title !== it.name" class="nameSub">{{ it.title }}</span>
                </div>
              </div>
            </div>
          </td>
          <td class="muted">{{ it.lang }}</td>
          <td class="muted">{{ formatKiB(it.size) }}</td>
          <td class="muted">{{ formatTime(it.mtimeIso) }}</td>
          <td class="actions">
            <a class="actionLink" :href="it.mdUrl" download>{{ t(uiLang, '下载', 'Download') }}</a>
            <BaseButton
              :variant="copiedKey === it.id ? 'primary' : 'default'"
              @click="copy(it.id, it.mdUrl)"
            >
              {{ copiedKey === it.id ? t(uiLang, '已复制', 'Copied') : t(uiLang, '复制链接', 'Copy') }}
            </BaseButton>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import type { CatalogItem } from '../models/catalog';
import type { UiLang } from '../i18n';
import { t } from '../i18n';
import BaseButton from './BaseButton.vue';

defineProps<{
  items: Array<CatalogItem>;
  uiLang: UiLang;
}>();

const copiedKey = ref<string>('');
let copyTimer: number | undefined;

function formatKiB(bytes: number): string {
  const n = typeof bytes === 'number' ? bytes : 0;
  const kib = n / 1024;
  if (kib < 1024) return `${kib.toFixed(1)} KiB`;
  return `${(kib / 1024).toFixed(1)} MiB`;
}

function formatTime(iso: string): string {
  const s = String(iso ?? '').trim();
  return s ? s.replace('T', ' ').replace('Z', '') : '';
}

function avatarText(label: string): string {
  const trimmed = String(label ?? '').trim();
  if (!trimmed) return '?';
  const chars = Array.from(trimmed);
  let picked = chars[0] ?? '?';
  if (picked === '.' && chars.length > 1) {
    picked = chars[1];
  }
  return String(picked).toUpperCase();
}

function copy(key: string, url: string): void {
  const u = String(url ?? '').trim();
  if (!u) return;

  const clear = () => {
    copiedKey.value = '';
    copyTimer = undefined;
  };

  navigator.clipboard.writeText(u).then(
    () => {
      copiedKey.value = key;
      if (copyTimer) window.clearTimeout(copyTimer);
      copyTimer = window.setTimeout(clear, 1500);
    },
    () => undefined,
  );
}
</script>

<style scoped>
.tableWrap {
  overflow: auto;
}

.table {
  width: 100%;
  border-collapse: collapse;
}

thead th {
  text-align: left;
  font-weight: 700;
  font-size: 0.95rem;
  padding: 0.75rem 0.9rem;
  border-bottom: 0.0625rem solid var(--border);
  background: color-mix(in srgb, var(--card) 90%, var(--bg) 10%);
  position: sticky;
  top: 0;
}

tbody td {
  padding: 0.75rem 0.9rem;
  border-bottom: 0.0625rem solid var(--border);
  vertical-align: top;
}

tbody tr:hover {
  background: color-mix(in srgb, var(--card) 84%, var(--bg) 16%);
}

.colSmall {
  white-space: nowrap;
}

.path {
  min-width: 22rem;
  font-size: 0.95rem;
  word-break: break-word;
}

.docRow {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
}

.avatar {
  width: 2.25rem;
  height: 2.25rem;
  flex: 0 0 auto;
  border-radius: 0.65rem;
  overflow: hidden;
  border: 0.0625rem solid var(--border);
  background: color-mix(in srgb, var(--card) 70%, var(--bg) 30%);
  display: grid;
  place-items: center;
}

.avatarImg {
  width: 100%;
  height: 100%;
  object-fit: contain;
}

.avatarFallback {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  font-weight: 800;
  font-size: 1rem;
  color: color-mix(in srgb, var(--fg) 70%, var(--bg) 30%);
}

.docText {
  min-width: 0;
}

.name {
  margin-top: 0.25rem;
  color: var(--muted);
  display: grid;
  gap: 0.15rem;
}

.nameMain {
  font-weight: 600;
  color: var(--fg);
}

.nameSub {
  font-size: 0.9rem;
}

.muted {
  white-space: nowrap;
  color: var(--muted);
  font-size: 0.95rem;
}

.actions {
  display: inline-flex;
  gap: 0.5rem;
  align-items: center;
  white-space: nowrap;
}

.actionLink {
  color: var(--link);
  font-size: 0.95rem;
}

@media (max-width: 48rem) {
  thead th:nth-child(4),
  tbody td:nth-child(4) {
    display: none;
  }
}

@media (max-width: 36rem) {
  thead th:nth-child(3),
  tbody td:nth-child(3) {
    display: none;
  }
}
</style>

