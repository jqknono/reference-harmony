<template>
  <div class="wrap">
    <header class="header">
      <div class="titleRow">
        <h1 class="title">{{ t(uiLang, '备忘清单 文件列表', 'Cheat Sheet File List') }}</h1>
        <BaseButton class="langBtn" @click="toggleUiLang">
          {{ uiLang === 'zh' ? 'English' : '中文' }}
        </BaseButton>
      </div>
      <div class="meta">
        <span>{{ t(uiLang, '开源地址', 'Source') }}：</span>
        <a href="https://github.com/jqknono/reference-harmony" target="_blank" rel="noreferrer">GitHub</a>
        <span class="sep">·</span>
        <span>{{ t(uiLang, '文件数', 'Files') }}：{{ filteredCount }}</span>
        <span v-if="builtAtText" class="sep">·</span>
        <span v-if="builtAtText">{{ t(uiLang, '构建时间', 'Built at') }}：{{ builtAtText }}</span>
      </div>
    </header>

    <div class="card">
      <div class="toolbar">
        <div class="field">
          <label class="label">{{ t(uiLang, '语言', 'Lang') }}</label>
          <select class="select" v-model="langFilter">
            <option value="all">{{ t(uiLang, '全部', 'All') }}</option>
            <option value="zh">{{ t(uiLang, '中文', 'ZH') }}</option>
            <option value="en">{{ t(uiLang, '英文', 'EN') }}</option>
          </select>
        </div>
        <div class="field fieldGrow">
          <label class="label">{{ t(uiLang, '搜索（按路径/标题过滤）', 'Search (path/title)') }}</label>
          <BaseInput v-model="query" :placeholder="t(uiLang, '例如：zh/git 或 docker', 'e.g. en/git or docker')" />
        </div>
        <div class="field">
          <label class="label">&nbsp;</label>
          <BaseButton :disabled="loading" @click="reload">
            {{ loading ? t(uiLang, '加载中…', 'Loading…') : t(uiLang, '刷新', 'Reload') }}
          </BaseButton>
        </div>
      </div>

      <div v-if="errorText" class="error">{{ errorText }}</div>
      <div v-else-if="loading" class="hint">{{ t(uiLang, '加载中…', 'Loading…') }}</div>
      <div v-else>
        <CatalogTable :items="filteredItems" :ui-lang="uiLang" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import BaseInput from './components/BaseInput.vue';
import BaseButton from './components/BaseButton.vue';
import CatalogTable from './components/CatalogTable.vue';
import type { CatalogItem } from './models/catalog';
import { fetchCatalog, type CatalogQueryLang } from './api/catalog';
import { detectUiLang, t, type UiLang } from './i18n';

const uiLang = ref<UiLang>(detectUiLang());
const langFilter = ref<CatalogQueryLang>('all');
const query = ref<string>('');

const loading = ref<boolean>(false);
const errorText = ref<string>('');
const allItems = ref<Array<CatalogItem>>([]);
const builtAtText = ref<string>('');

const filteredItems = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return allItems.value;
  return allItems.value.filter((it) => {
    const hay = [it.relPath, it.name, it.title, it.id].join(' ').toLowerCase();
    return hay.includes(q);
  });
});

const filteredCount = computed(() => filteredItems.value.length);

function toggleUiLang(): void {
  uiLang.value = uiLang.value === 'zh' ? 'en' : 'zh';
}

function load(): void {
  if (loading.value) return;
  loading.value = true;
  errorText.value = '';
  allItems.value = [];

  fetchCatalog(langFilter.value).then(
    (resp) => {
      allItems.value = resp.items ?? [];
      builtAtText.value = String(resp.builtAt ?? '').replace('T', ' ').replace('Z', '');
      loading.value = false;
    },
    (e) => {
      errorText.value = String(e ?? '');
      loading.value = false;
    },
  );
}

function reload(): void {
  load();
}

onMounted(() => {
  load();
});
</script>

<style scoped>
.wrap {
  max-width: 72rem;
  margin: 0 auto;
  padding: 1.25rem;
}

.header {
  display: grid;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.titleRow {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  justify-content: space-between;
}

.title {
  font-size: 1.5rem;
  line-height: 1.2;
  margin: 0;
}

.langBtn {
  white-space: nowrap;
}

.meta {
  color: var(--muted);
  font-size: 0.95rem;
}

.sep {
  margin: 0 0.4rem;
}

.card {
  background: var(--card);
  border: 0.0625rem solid var(--border);
  border-radius: 0.75rem;
  overflow: hidden;
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.9rem;
  padding: 0.9rem;
  border-bottom: 0.0625rem solid var(--border);
  align-items: end;
}

.field {
  display: grid;
  gap: 0.35rem;
  min-width: 10rem;
}

.fieldGrow {
  flex: 1;
  min-width: 16rem;
}

.label {
  font-weight: 600;
  font-size: 0.95rem;
}

.select {
  width: 100%;
  border: 0.0625rem solid var(--border);
  border-radius: 0.6rem;
  padding: 0.62rem 0.75rem;
  background: var(--bg);
  color: var(--fg);
  font: inherit;
  outline: none;
}

.select:focus {
  border-color: color-mix(in srgb, var(--accent) 60%, var(--border) 40%);
}

.hint {
  padding: 1rem;
  color: var(--muted);
}

.error {
  padding: 1rem;
  color: var(--danger);
  white-space: pre-wrap;
}
</style>

