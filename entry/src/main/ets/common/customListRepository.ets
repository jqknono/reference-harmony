// 自定义清单存储仓库 - 记忆表格模式

import preferences from '@ohos.data.preferences';
import util from '@ohos.util';
import type {
  CustomList,
  CustomListCollection,
  SharedListData,
  ReviewGrade,
  ListSection,
  MemoryTable,
  MemoryTableRow,
  MemoryTableCell,
} from './customListModels';
import { OnlineShareRepository } from './onlineShareRepository';
import {
  createEmptyCustomListCollection,
  generateCustomListId,
  generateSectionId,
  generateTableId,
  generateRowId,
  generateShareId,
  calculateNextReview,
  calculateChecksum,
  listToMarkdown,
} from './customListModels';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

const CUSTOM_LISTS_KEY = 'custom_lists';
const MAX_LISTS_STORED = 100;
const SHARE_DATA_VERSION = 2;

function isRecord(value: Object | null | undefined): boolean {
  return typeof value === 'object' && value !== null;
}

function toStringOrEmpty(value: Object | null | undefined, markChanged?: () => void): string {
  if (typeof value === 'string') return value;
  markChanged?.();
  return '';
}

function toOptionalString(value: Object | null | undefined, markChanged?: () => void): string | undefined {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed ? trimmed : undefined;
  }
  if (value === undefined || value === null) return undefined;
  markChanged?.();
  return undefined;
}

function toNumberOr(value: Object | null | undefined, fallback: number, markChanged?: () => void): number {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : fallback;
  }
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  if (value !== undefined && value !== null) {
    markChanged?.();
  }
  return fallback;
}

function toBooleanOr(value: Object | null | undefined, fallback: boolean, markChanged?: () => void): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') return value === 'true' || value === '1';
  if (value !== undefined && value !== null) {
    markChanged?.();
  }
  return fallback;
}

function clampInt(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  const n = Math.floor(value);
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function sanitizeMemoryTableCell(raw: Object | null | undefined, markChanged: () => void): MemoryTableCell {
  if (!isRecord(raw)) {
    markChanged();
    return { text: '' };
  }
  const obj = raw as Record<string, Object>;
  return {
    text: toStringOrEmpty(obj['text'] as Object | null | undefined, markChanged),
  };
}

function sanitizeMemoryTableRow(raw: Object | null | undefined, markChanged: () => void, usedIds: Set<string>): MemoryTableRow | null {
  if (!isRecord(raw)) {
    markChanged();
    return null;
  }
  const obj = raw as Record<string, Object>;

  let id: string = toStringOrEmpty(obj['id'] as Object | null | undefined, markChanged).trim();
  if (!id) {
    markChanged();
    id = generateRowId();
  }
  if (usedIds.has(id)) {
    markChanged();
    id = generateRowId();
  }
  usedIds.add(id);

  const now = Date.now();
  const cellsRaw = obj['cells'] as Object | null | undefined;
  const cells: Array<MemoryTableCell> = [];
  if (Array.isArray(cellsRaw)) {
    for (const c of cellsRaw as Array<Object>) {
      cells.push(sanitizeMemoryTableCell(c, markChanged));
    }
  } else {
    markChanged();
  }

  const reviewCount = Math.max(0, clampInt(toNumberOr(obj['reviewCount'] as Object | null | undefined, 0, markChanged), 0, 1_000_000));
  const lastReviewAt = Math.max(0, toNumberOr(obj['lastReviewAt'] as Object | null | undefined, 0, markChanged));
  const nextReviewAt = Math.max(0, toNumberOr(obj['nextReviewAt'] as Object | null | undefined, now, markChanged));
  const easeFactor = (() => {
    const v = toNumberOr(obj['easeFactor'] as Object | null | undefined, 2.5, markChanged);
    if (!Number.isFinite(v)) return 2.5;
    return Math.max(1.3, Math.min(3.0, v));
  })();
  const interval = Math.max(0, clampInt(toNumberOr(obj['interval'] as Object | null | undefined, 0, markChanged), 0, 36500));

  const lastGradeRaw = toNumberOr(obj['lastGrade'] as Object | null | undefined, -1, markChanged);
  const lastGrade = lastGradeRaw === 0 || lastGradeRaw === 1 || lastGradeRaw === 2 || lastGradeRaw === 3 ? lastGradeRaw : undefined;

  return {
    id,
    cells,
    reviewCount,
    lastReviewAt,
    nextReviewAt,
    easeFactor,
    interval,
    lastGrade,
  };
}

function sanitizeMemoryTable(raw: Object | null | undefined, markChanged: () => void, usedIds: Set<string>): MemoryTable | null {
  if (!isRecord(raw)) {
    markChanged();
    return null;
  }
  const obj = raw as Record<string, Object>;

  let id: string = toStringOrEmpty(obj['id'] as Object | null | undefined, markChanged).trim();
  if (!id) {
    markChanged();
    id = generateTableId();
  }
  if (usedIds.has(id)) {
    markChanged();
    id = generateTableId();
  }
  usedIds.add(id);

  const now = Date.now();
  const headersRaw = obj['headers'] as Object | null | undefined;
  const headers: Array<string> = [];
  if (Array.isArray(headersRaw)) {
    for (const h of headersRaw as Array<Object>) {
      headers.push(toStringOrEmpty(h, markChanged));
    }
  } else {
    markChanged();
    headers.push('');
    headers.push('');
  }

  const rowsRaw = obj['rows'] as Object | null | undefined;
  const usedRowIds = new Set<string>();
  const rows: Array<MemoryTableRow> = [];
  if (Array.isArray(rowsRaw)) {
    for (const r of rowsRaw as Array<Object>) {
      const row = sanitizeMemoryTableRow(r, markChanged, usedRowIds);
      if (row) rows.push(row);
    }
  } else if (rowsRaw !== undefined && rowsRaw !== null) {
    markChanged();
  }

  const createdAt = toNumberOr(obj['createdAt'] as Object | null | undefined, now, markChanged);
  const updatedAt = toNumberOr(obj['updatedAt'] as Object | null | undefined, createdAt, markChanged);

  return {
    id,
    headers,
    rows,
    createdAt,
    updatedAt,
  };
}

function sanitizeListSection(raw: Object | null | undefined, markChanged: () => void, usedIds: Set<string>): ListSection | null {
  if (!isRecord(raw)) {
    markChanged();
    return null;
  }
  const obj = raw as Record<string, Object>;

  let id: string = toStringOrEmpty(obj['id'] as Object | null | undefined, markChanged).trim();
  if (!id) {
    markChanged();
    id = generateSectionId();
  }
  if (usedIds.has(id)) {
    markChanged();
    id = generateSectionId();
  }
  usedIds.add(id);

  const now = Date.now();
  const level = clampInt(toNumberOr(obj['level'] as Object | null | undefined, 2, markChanged), 1, 6);
  const title = (() => {
    const t = toStringOrEmpty(obj['title'] as Object | null | undefined, markChanged).trim();
    if (t) return t;
    markChanged();
    return 'Untitled';
  })();
  const content = toStringOrEmpty(obj['content'] as Object | null | undefined, markChanged);

  const tablesRaw = obj['tables'] as Object | null | undefined;
  const usedTableIds = new Set<string>();
  const tables: Array<MemoryTable> = [];
  if (Array.isArray(tablesRaw)) {
    for (const t of tablesRaw as Array<Object>) {
      const table = sanitizeMemoryTable(t, markChanged, usedTableIds);
      if (table) tables.push(table);
    }
  } else if (tablesRaw !== undefined && tablesRaw !== null) {
    markChanged();
  }

  const createdAt = toNumberOr(obj['createdAt'] as Object | null | undefined, now, markChanged);
  const updatedAt = toNumberOr(obj['updatedAt'] as Object | null | undefined, createdAt, markChanged);

  return {
    id,
    level,
    title,
    content,
    tables,
    createdAt,
    updatedAt,
  };
}

function sanitizeCustomList(raw: Object | null | undefined, markChanged: () => void, usedListIds: Set<string>): CustomList | null {
  if (!isRecord(raw)) {
    markChanged();
    return null;
  }
  const obj = raw as Record<string, Object>;

  let id: string = toStringOrEmpty(obj['id'] as Object | null | undefined, markChanged).trim();
  if (!id) {
    markChanged();
    id = generateCustomListId();
  }
  if (usedListIds.has(id)) {
    markChanged();
    id = generateCustomListId();
  }
  usedListIds.add(id);

  const now = Date.now();
  const name: string = (() => {
    const n = toStringOrEmpty(obj['name'] as Object | null | undefined, markChanged).trim();
    if (n) return n;
    markChanged();
    return 'Untitled';
  })();

  const createdAt: number = toNumberOr(obj['createdAt'] as Object | null | undefined, now, markChanged);
  const updatedAt: number = toNumberOr(obj['updatedAt'] as Object | null | undefined, createdAt, markChanged);

  const sectionsRaw: Object | null | undefined = obj['sections'] as Object | null | undefined;
  const usedSectionIds: Set<string> = new Set<string>();
  const sections: Array<ListSection> = [];
  if (Array.isArray(sectionsRaw)) {
    const arr = sectionsRaw as Array<Object>;
    for (const s of arr) {
      const section = sanitizeListSection(s, markChanged, usedSectionIds);
      if (section) sections.push(section);
    }
  } else if (sectionsRaw !== undefined && sectionsRaw !== null) {
    markChanged();
  }

  return {
    id,
    name,
    description: toOptionalString(obj['description'] as Object | null | undefined, markChanged),
    icon: toOptionalString(obj['icon'] as Object | null | undefined, markChanged),
    sections,
    createdAt,
    updatedAt,
    shareId: toOptionalString(obj['shareId'] as Object | null | undefined, markChanged),
    sharePassword: toOptionalString(obj['sharePassword'] as Object | null | undefined, markChanged),
    isShared: toBooleanOr(obj['isShared'] as Object | null | undefined, false, markChanged),
    sharedAt: (() => {
      const t = toNumberOr(obj['sharedAt'] as Object | null | undefined, -1, markChanged);
      return Number.isFinite(t) && t > 0 ? t : undefined;
    })(),
  };
}

function sanitizeCustomListCollection(raw: Object | null | undefined, markChanged: () => void): CustomListCollection {
  const usedListIds: Set<string> = new Set<string>();
  const lists: Array<CustomList> = [];
  let lastSyncAt: number = 0;

  if (Array.isArray(raw)) {
    markChanged();
    const arr = raw as Array<Object>;
    for (const l of arr) {
      const list = sanitizeCustomList(l, markChanged, usedListIds);
      if (list) lists.push(list);
    }
    return { lists, lastSyncAt };
  }

  if (!isRecord(raw)) {
    markChanged();
    return createEmptyCustomListCollection();
  }
  const obj = raw as Record<string, Object>;

  lastSyncAt = Math.max(0, toNumberOr(obj['lastSyncAt'] as Object | null | undefined, 0, markChanged));
  const rawLists: Object | null | undefined = obj['lists'] as Object | null | undefined;
  if (Array.isArray(rawLists)) {
    const arr = rawLists as Array<Object>;
    for (const l of arr) {
      const list = sanitizeCustomList(l, markChanged, usedListIds);
      if (list) lists.push(list);
    }
  } else {
    markChanged();
  }

  return { lists, lastSyncAt };
}

/**
 * 加密/解密工具 (使用 Base64 + 简单 XOR 混淆)
 */
function encryptData(data: string, password: string): string {
  const encoder = new util.TextEncoder();
  const bytes = encoder.encodeInto(data);
  const passBytes = encoder.encodeInto(password);
  const encrypted = new Uint8Array(bytes.length);

  for (let i = 0; i < bytes.length; i++) {
    encrypted[i] = bytes[i] ^ passBytes[i % passBytes.length];
  }

  const base64 = new util.Base64Helper();
  return base64.encodeToStringSync(encrypted);
}

function decryptData(encrypted: string, password: string): string {
  const base64 = new util.Base64Helper();
  const bytes = base64.decodeSync(encrypted);
  const encoder = new util.TextEncoder();
  const passBytes = encoder.encodeInto(password);
  const decrypted = new Uint8Array(bytes.length);

  for (let i = 0; i < bytes.length; i++) {
    decrypted[i] = bytes[i] ^ passBytes[i % passBytes.length];
  }

  const decoder = new util.TextDecoder('utf-8');
  return decoder.decodeToString(decrypted);
}

function looksLikeBase64Payload(data: string): boolean {
  const s = String(data ?? '').trim();
  if (!s) return false;
  if (s.startsWith('ENC:')) return false;
  // base64 payload should not contain whitespace
  if (/\s/.test(s)) return false;
  // avoid false positives on short strings
  if (s.length < 16) return false;
  // padding aligned
  if (s.length % 4 !== 0) return false;
  // standard base64 (allow URL-safe variants too)
  return /^[A-Za-z0-9+/=_-]+$/.test(s);
}

/**
 * 复制 MemoryTableCell 对象
 */
function copyCell(cell: MemoryTableCell): MemoryTableCell {
  return { text: cell.text };
}

/**
 * 复制 MemoryTableRow 对象
 */
function copyRow(row: MemoryTableRow): MemoryTableRow {
  const cells: Array<MemoryTableCell> = [];
  for (const cell of row.cells) {
    cells.push(copyCell(cell));
  }
  return {
    id: row.id,
    cells,
    reviewCount: row.reviewCount,
    lastReviewAt: row.lastReviewAt,
    nextReviewAt: row.nextReviewAt,
    easeFactor: row.easeFactor,
    interval: row.interval,
    lastGrade: row.lastGrade,
  };
}

/**
 * 复制 MemoryTable 对象
 */
function copyTable(table: MemoryTable): MemoryTable {
  const headers: Array<string> = [];
  for (const h of table.headers) {
    headers.push(h);
  }
  const rows: Array<MemoryTableRow> = [];
  for (const row of table.rows) {
    rows.push(copyRow(row));
  }
  return {
    id: table.id,
    headers,
    rows,
    createdAt: table.createdAt,
    updatedAt: table.updatedAt,
  };
}

/**
 * 复制 ListSection 对象
 */
function copySection(section: ListSection): ListSection {
  const tables: Array<MemoryTable> = [];
  for (const table of section.tables) {
    tables.push(copyTable(table));
  }
  return {
    id: section.id,
    level: section.level,
    title: section.title,
    content: section.content,
    tables,
    createdAt: section.createdAt,
    updatedAt: section.updatedAt,
  };
}

/**
 * 复制 CustomList 对象
 */
function copyList(list: CustomList): CustomList {
  const sections: Array<ListSection> = [];
  for (const section of list.sections) {
    sections.push(copySection(section));
  }
  return {
    id: list.id,
    name: list.name,
    description: list.description,
    icon: list.icon,
    sections,
    createdAt: list.createdAt,
    updatedAt: list.updatedAt,
    shareId: list.shareId,
    sharePassword: list.sharePassword,
    isShared: list.isShared,
    sharedAt: list.sharedAt,
  };
}

/**
 * 合并更新到 CustomList
 */
function mergeListUpdates(list: CustomList, updates: Partial<CustomList>): CustomList {
  return {
    id: list.id,
    name: updates.name !== undefined ? updates.name : list.name,
    description: updates.description !== undefined ? updates.description : list.description,
    icon: updates.icon !== undefined ? updates.icon : list.icon,
    sections: updates.sections !== undefined ? updates.sections : list.sections,
    createdAt: list.createdAt,
    updatedAt: Date.now(),
    shareId: updates.shareId !== undefined ? updates.shareId : list.shareId,
    sharePassword: updates.sharePassword !== undefined ? updates.sharePassword : list.sharePassword,
    isShared: updates.isShared !== undefined ? updates.isShared : list.isShared,
    sharedAt: updates.sharedAt !== undefined ? updates.sharedAt : list.sharedAt,
  };
}

export class CustomListRepository {
  private readonly prefsName: string = 'custom_lists_data';
  private readonly onlineShareRepository: OnlineShareRepository = new OnlineShareRepository();

  private async getPrefs(context: Context): Promise<Preferences | undefined> {
    return Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, this.prefsName))
      .then(
        (p: Preferences): Preferences => p,
        (): undefined => undefined,
      );
  }

  /**
   * 获取所有自定义清单
   */
  async getCustomLists(context: Context): Promise<CustomListCollection> {
    const prefs = await this.getPrefs(context);
    if (!prefs) {
      return createEmptyCustomListCollection();
    }

    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(CUSTOM_LISTS_KEY, ''))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : ''),
        (): string => '',
      );

    if (!saved) {
      return createEmptyCustomListCollection();
    }

    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(saved) as Object | null;
    } catch (_) {
      return createEmptyCustomListCollection();
    }

    let changed = false;
    const markChanged = (): void => {
      changed = true;
    };

    const sanitized: CustomListCollection = sanitizeCustomListCollection(parsed, markChanged);

    if (changed) {
      await this.saveCustomLists(context, sanitized);
    }

    return sanitized;
  }

  /**
   * 保存所有自定义清单
   */
  async saveCustomLists(context: Context, collection: CustomListCollection): Promise<void> {
    const prefs = await this.getPrefs(context);
    if (!prefs) return;

    if (collection.lists.length > MAX_LISTS_STORED) {
      collection.lists = collection.lists.slice(0, MAX_LISTS_STORED);
    }

    collection.lastSyncAt = Date.now();
    const json = JSON.stringify(collection);

    await Promise.resolve()
      .then((): Promise<void> => prefs.put(CUSTOM_LISTS_KEY, json))
      .then((): void => undefined, (): void => undefined);

    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  /**
   * 添加新清单
   */
  async addList(context: Context, list: CustomList): Promise<CustomListCollection> {
    const collection = await this.getCustomLists(context);
    collection.lists.unshift(list);
    await this.saveCustomLists(context, collection);
    return collection;
  }

  /**
   * 更新清单
   */
  async updateList(context: Context, listId: string, updates: Partial<CustomList>): Promise<CustomListCollection> {
    const collection = await this.getCustomLists(context);
    const index = collection.lists.findIndex(l => l.id === listId);
    if (index >= 0) {
      collection.lists[index] = mergeListUpdates(collection.lists[index], updates);
      await this.saveCustomLists(context, collection);
    }
    return collection;
  }

  /**
   * 删除清单
   */
  async deleteList(context: Context, listId: string): Promise<CustomListCollection> {
    const collection = await this.getCustomLists(context);
    collection.lists = collection.lists.filter(l => l.id !== listId);
    await this.saveCustomLists(context, collection);
    return collection;
  }

  /**
   * 获取单个清单
   */
  async getList(context: Context, listId: string): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    return collection.lists.find(l => l.id === listId);
  }

  /**
   * 添加章节
   */
  async addSection(context: Context, listId: string, section: ListSection): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      list.sections.push(section);
      list.updatedAt = Date.now();
      await this.saveCustomLists(context, collection);
    }
    return list;
  }

  /**
   * 更新章节
   */
  async updateSection(context: Context, listId: string, sectionId: string, updates: Partial<ListSection>): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const sectionIndex = list.sections.findIndex(s => s.id === sectionId);
      if (sectionIndex >= 0) {
        const section = list.sections[sectionIndex];
        list.sections[sectionIndex] = {
          id: section.id,
          level: updates.level !== undefined ? updates.level : section.level,
          title: updates.title !== undefined ? updates.title : section.title,
          content: updates.content !== undefined ? updates.content : section.content,
          tables: updates.tables !== undefined ? updates.tables : section.tables,
          createdAt: section.createdAt,
          updatedAt: Date.now(),
        };
        list.updatedAt = Date.now();
        await this.saveCustomLists(context, collection);
      }
    }
    return list;
  }

  /**
   * 删除章节
   */
  async deleteSection(context: Context, listId: string, sectionId: string): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      list.sections = list.sections.filter(s => s.id !== sectionId);
      list.updatedAt = Date.now();
      await this.saveCustomLists(context, collection);
    }
    return list;
  }

  /**
   * 添加表格到章节
   */
  async addTable(context: Context, listId: string, sectionId: string, table: MemoryTable): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        section.tables.push(table);
        section.updatedAt = Date.now();
        list.updatedAt = Date.now();
        await this.saveCustomLists(context, collection);
      }
    }
    return list;
  }

  /**
   * 更新表格
   */
  async updateTable(context: Context, listId: string, sectionId: string, tableId: string, updates: Partial<MemoryTable>): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        const tableIndex = section.tables.findIndex(t => t.id === tableId);
        if (tableIndex >= 0) {
          const table = section.tables[tableIndex];
          section.tables[tableIndex] = {
            id: table.id,
            headers: updates.headers !== undefined ? updates.headers : table.headers,
            rows: updates.rows !== undefined ? updates.rows : table.rows,
            createdAt: table.createdAt,
            updatedAt: Date.now(),
          };
          section.updatedAt = Date.now();
          list.updatedAt = Date.now();
          await this.saveCustomLists(context, collection);
        }
      }
    }
    return list;
  }

  /**
   * 删除表格
   */
  async deleteTable(context: Context, listId: string, sectionId: string, tableId: string): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        section.tables = section.tables.filter(t => t.id !== tableId);
        section.updatedAt = Date.now();
        list.updatedAt = Date.now();
        await this.saveCustomLists(context, collection);
      }
    }
    return list;
  }

  /**
   * 添加表格行
   */
  async addRow(context: Context, listId: string, sectionId: string, tableId: string, row: MemoryTableRow): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        const table = section.tables.find(t => t.id === tableId);
        if (table) {
          table.rows.push(row);
          table.updatedAt = Date.now();
          section.updatedAt = Date.now();
          list.updatedAt = Date.now();
          await this.saveCustomLists(context, collection);
        }
      }
    }
    return list;
  }

  /**
   * 更新表格行
   */
  async updateRow(context: Context, listId: string, sectionId: string, tableId: string, rowId: string, updates: Partial<MemoryTableRow>): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        const table = section.tables.find(t => t.id === tableId);
        if (table) {
          const rowIndex = table.rows.findIndex(r => r.id === rowId);
          if (rowIndex >= 0) {
            const row = table.rows[rowIndex];
            table.rows[rowIndex] = {
              id: row.id,
              cells: updates.cells !== undefined ? updates.cells : row.cells,
              reviewCount: updates.reviewCount !== undefined ? updates.reviewCount : row.reviewCount,
              lastReviewAt: updates.lastReviewAt !== undefined ? updates.lastReviewAt : row.lastReviewAt,
              nextReviewAt: updates.nextReviewAt !== undefined ? updates.nextReviewAt : row.nextReviewAt,
              easeFactor: updates.easeFactor !== undefined ? updates.easeFactor : row.easeFactor,
              interval: updates.interval !== undefined ? updates.interval : row.interval,
              lastGrade: updates.lastGrade !== undefined ? updates.lastGrade : row.lastGrade,
            };
            table.updatedAt = Date.now();
            section.updatedAt = Date.now();
            list.updatedAt = Date.now();
            await this.saveCustomLists(context, collection);
          }
        }
      }
    }
    return list;
  }

  /**
   * 删除表格行
   */
  async deleteRow(context: Context, listId: string, sectionId: string, tableId: string, rowId: string): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const section = list.sections.find(s => s.id === sectionId);
      if (section) {
        const table = section.tables.find(t => t.id === tableId);
        if (table) {
          table.rows = table.rows.filter(r => r.id !== rowId);
          table.updatedAt = Date.now();
          section.updatedAt = Date.now();
          list.updatedAt = Date.now();
          await this.saveCustomLists(context, collection);
        }
      }
    }
    return list;
  }

  /**
   * 记录复习结果
   */
  async recordReview(
    context: Context,
    listId: string,
    sectionId: string,
    tableId: string,
    rowId: string,
    grade: ReviewGrade
  ): Promise<MemoryTableRow | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (!list) return undefined;

    const section = list.sections.find(s => s.id === sectionId);
    if (!section) return undefined;

    const table = section.tables.find(t => t.id === tableId);
    if (!table) return undefined;

    const rowIndex = table.rows.findIndex(r => r.id === rowId);
    if (rowIndex < 0) return undefined;

    const updatedRow = calculateNextReview(table.rows[rowIndex], grade);
    table.rows[rowIndex] = updatedRow;
    table.updatedAt = Date.now();
    section.updatedAt = Date.now();
    list.updatedAt = Date.now();
    await this.saveCustomLists(context, collection);
    return updatedRow;
  }

  /**
   * 导出清单为分享数据（可选加密）
   */
  exportListForShare(list: CustomList, password?: string): string {
    const exportList: CustomList = {
      id: list.id,
      name: list.name,
      description: list.description,
      icon: list.icon,
      sections: list.sections,
      createdAt: list.createdAt,
      updatedAt: list.updatedAt,
      shareId: undefined,
      sharePassword: undefined,
      isShared: false,
      sharedAt: undefined,
    };

    const shareData: SharedListData = {
      version: SHARE_DATA_VERSION,
      list: exportList,
      exportedAt: Date.now(),
      checksum: '',
    };

    const jsonData = JSON.stringify(shareData);
    shareData.checksum = calculateChecksum(jsonData);
    const finalJson = JSON.stringify(shareData);

    if (password && password.length > 0) {
      const encrypted = encryptData(finalJson, password);
      return `ENC:${encrypted}`;
    }

    const base64 = new util.Base64Helper();
    const encoder = new util.TextEncoder();
    return base64.encodeToStringSync(encoder.encodeInto(finalJson));
  }

  /**
   * 导入分享数据
   */
  importShareData(data: string, password?: string): SharedListData | null {
    let jsonData: string = '';
    try {
      if (data.startsWith('ENC:')) {
        if (!password || password.length === 0) {
          return null;
        }
        const encrypted = data.slice(4);
        jsonData = decryptData(encrypted, password);
      } else {
        const base64 = new util.Base64Helper();
        const decoded = base64.decodeSync(data);
        const decoder = new util.TextDecoder('utf-8');
        jsonData = decoder.decodeToString(decoded);
      }
    } catch (_) {
      return null;
    }

    let shareDataObj: Object | null = null;
    try {
      shareDataObj = JSON.parse(jsonData) as Object | null;
    } catch (_) {
      return null;
    }

    if (!isRecord(shareDataObj)) {
      return null;
    }
    const obj = shareDataObj as Record<string, Object>;

    let changed = false;
    const markChanged = (): void => {
      changed = true;
    };

    const normalizedList = sanitizeCustomList(obj['list'] as Object | null | undefined, markChanged, new Set<string>());
    if (!normalizedList) return null;

    const shareData: SharedListData = {
      version: clampInt(toNumberOr(obj['version'] as Object | null | undefined, SHARE_DATA_VERSION, markChanged), 1, 9999),
      list: normalizedList,
      exportedAt: toNumberOr(obj['exportedAt'] as Object | null | undefined, Date.now(), markChanged),
      checksum: toStringOrEmpty(obj['checksum'] as Object | null | undefined, markChanged),
    };

    return shareData;
  }

  /**
   * 生成分享链接（上传Markdown）
   */
  async generateShareLink(context: Context, listId: string, password?: string): Promise<string | null> {
    const list = await this.getList(context, listId);
    if (!list) return null;

    // 导出为Markdown
    const markdown = listToMarkdown(list);

    // 如果有密码，加密Markdown内容；否则直接上传Markdown原文
    let shareData: string;
    if (password && password.length > 0) {
      shareData = `ENC:${encryptData(markdown, password)}`;
    } else {
      shareData = markdown;
    }

    const result = await this.onlineShareRepository.createShare(shareData).then(
      (r) => r,
      () => null,
    );
    if (!result) return null;

    await this.updateList(context, listId, {
      shareId: result.id || generateShareId(),
      sharePassword: password,
      isShared: true,
      sharedAt: Date.now(),
    });

    return result.url || result.deepLink;
  }

  /**
   * 从分享链接导入清单
   */
  async importFromShareLink(
    context: Context,
    shareLink: string,
    password?: string
  ): Promise<CustomList | null> {
    const trimmed = String(shareLink ?? '').trim();
    if (!trimmed) return null;

    // 尝试解析新格式链接
    let shareId: string = '';
    let apiOriginOverride: string = '';

    const urlMatch = trimmed.match(/^https?:\/\/([^/]+)(\/.*)?$/i);
    if (urlMatch) {
      const idMatch = trimmed.match(/\/share\/([^/?#]+)/i);
      if (idMatch) {
        shareId = decodeURIComponent(idMatch[1]);
        shareId = shareId.replace(/\.(md|markdown)$/i, '');
        const originMatch = trimmed.match(/^(https?:\/\/[^/?#]+)/i);
        apiOriginOverride = originMatch ? originMatch[1] : '';
      }
    } else {
      const deepMatch = trimmed.match(/refhm:\/\/share\/([^/?#]+)/i);
      if (deepMatch) {
        shareId = decodeURIComponent(deepMatch[1]);
        shareId = shareId.replace(/\.(md|markdown)$/i, '');
      }
    }

    if (!shareId) {
      // 尝试直接解析数据
      return this.importFromShareData(context, trimmed, password);
    }

    const remoteData = await this.onlineShareRepository.fetchShareData(shareId, apiOriginOverride).then(
      (d) => d,
      () => '',
    );
    if (!remoteData) return null;

    return this.importFromShareData(context, remoteData, password);
  }

  /**
   * 从分享数据导入清单
   */
  private async importFromShareData(context: Context, data: string, password?: string): Promise<CustomList | null> {
    const raw = String(data ?? '').trim();
    if (!raw) return null;

    // 兼容旧格式：JSON 分享数据（可能是 base64 或 ENC 包裹）
    const legacyShareData = this.importShareData(raw, password);
    if (legacyShareData) {
      return this.importSharedList(context, legacyShareData);
    }

    let markdown: string = raw;
    try {
      if (raw.startsWith('ENC:')) {
        if (!password || password.length === 0) return null;
        markdown = decryptData(raw.slice(4), password);
      } else if (looksLikeBase64Payload(raw)) {
        const base64 = new util.Base64Helper();
        const decoded = base64.decodeSync(raw);
        const decoder = new util.TextDecoder('utf-8');
        markdown = decoder.decodeToString(decoded);
      }
    } catch (_) {
      return null;
    }

    // 从Markdown解析清单
    const models = await import('./customListModels');
    const newList = models.markdownToList(markdown);
    await this.addList(context, newList);
    return newList;
  }

  private async importSharedList(context: Context, shareData: SharedListData): Promise<CustomList | null> {
    const now = Date.now();
    const newSections: Array<ListSection> = [];

    for (const section of shareData.list.sections) {
      const newTables: Array<MemoryTable> = [];
      for (const table of section.tables) {
        const newRows: Array<MemoryTableRow> = [];
        for (const row of table.rows) {
          const newCells: Array<MemoryTableCell> = [];
          for (const cell of row.cells) {
            newCells.push({ text: cell.text });
          }
          newRows.push({
            id: generateRowId(),
            cells: newCells,
            reviewCount: 0,
            lastReviewAt: 0,
            nextReviewAt: now,
            easeFactor: 2.5,
            interval: 0,
          });
        }
        newTables.push({
          id: generateTableId(),
          headers: table.headers.slice(),
          rows: newRows,
          createdAt: now,
          updatedAt: now,
        });
      }
      newSections.push({
        id: generateSectionId(),
        level: section.level,
        title: section.title,
        content: section.content,
        tables: newTables,
        createdAt: now,
        updatedAt: now,
      });
    }

    const newList: CustomList = {
      id: generateCustomListId(),
      name: shareData.list.name,
      description: shareData.list.description,
      icon: shareData.list.icon,
      sections: newSections,
      createdAt: now,
      updatedAt: now,
      shareId: undefined,
      sharePassword: undefined,
      isShared: false,
      sharedAt: undefined,
    };

    await this.addList(context, newList);
    return newList;
  }

  /**
   * 清除所有数据
   */
  async clearAllData(context: Context): Promise<void> {
    const prefs = await this.getPrefs(context);
    if (!prefs) return;

    await Promise.resolve()
      .then((): Promise<void> => prefs.delete(CUSTOM_LISTS_KEY))
      .then((): void => undefined, (): void => undefined);

    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }
}
