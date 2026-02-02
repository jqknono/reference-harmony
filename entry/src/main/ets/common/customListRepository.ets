// 自定义清单存储仓库

import preferences from '@ohos.data.preferences';
import util from '@ohos.util';
import type {
  CustomList,
  CustomListItem,
  CustomListCollection,
  SharedListData,
  ReviewGrade,
} from './customListModels';
import { OnlineShareRepository } from './onlineShareRepository';
import {
  createEmptyCustomListCollection,
  generateCustomListId,
  generateCustomListItemId,
  generateShareId,
  calculateNextReview,
  calculateChecksum,
} from './customListModels';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

const CUSTOM_LISTS_KEY = 'custom_lists';
const MAX_LISTS_STORED = 100;
const SHARE_DATA_VERSION = 1;

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

function sanitizeCustomListItem(raw: Object | null | undefined, markChanged: () => void, usedIds: Set<string>): CustomListItem | null {
  if (!isRecord(raw)) {
    markChanged();
    return null;
  }
  const obj = raw as Record<string, Object>;

  let id: string = toStringOrEmpty(obj['id'] as Object | null | undefined, markChanged).trim();
  if (!id) {
    markChanged();
    id = generateCustomListItemId();
  }
  if (usedIds.has(id)) {
    markChanged();
    id = generateCustomListItemId();
  }
  usedIds.add(id);

  const now = Date.now();
  const title: string = toStringOrEmpty(obj['title'] as Object | null | undefined, markChanged);
  const content: string = toStringOrEmpty(obj['content'] as Object | null | undefined, markChanged);
  const createdAt: number = toNumberOr(obj['createdAt'] as Object | null | undefined, now, markChanged);
  const updatedAt: number = toNumberOr(obj['updatedAt'] as Object | null | undefined, createdAt, markChanged);

  const reviewCount: number = Math.max(
    0,
    clampInt(toNumberOr(obj['reviewCount'] as Object | null | undefined, 0, markChanged), 0, 1_000_000)
  );
  const lastReviewAt: number = Math.max(0, toNumberOr(obj['lastReviewAt'] as Object | null | undefined, 0, markChanged));
  const nextReviewAt: number = Math.max(
    0,
    toNumberOr(obj['nextReviewAt'] as Object | null | undefined, createdAt, markChanged)
  );
  const easeFactor: number = (() => {
    const v = toNumberOr(obj['easeFactor'] as Object | null | undefined, 2.5, markChanged);
    if (!Number.isFinite(v)) return 2.5;
    return Math.max(1.3, Math.min(3.0, v));
  })();
  const interval: number = Math.max(
    0,
    clampInt(toNumberOr(obj['interval'] as Object | null | undefined, 0, markChanged), 0, 36500)
  );

  const lastGradeRaw: number = toNumberOr(obj['lastGrade'] as Object | null | undefined, -1, markChanged);
  const lastGrade: number | undefined =
    lastGradeRaw === 0 || lastGradeRaw === 1 || lastGradeRaw === 2 || lastGradeRaw === 3 ? lastGradeRaw : undefined;

  return {
    id,
    title,
    content,
    answer: toOptionalString(obj['answer'] as Object | null | undefined, markChanged),
    createdAt,
    updatedAt,
    reviewCount,
    lastReviewAt,
    nextReviewAt,
    easeFactor,
    interval,
    lastGrade,
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

  const itemsRaw: Object | null | undefined = obj['items'] as Object | null | undefined;
  const usedItemIds: Set<string> = new Set<string>();
  const items: Array<CustomListItem> = [];
  if (Array.isArray(itemsRaw)) {
    const arr = itemsRaw as Array<Object>;
    for (const it of arr) {
      const item = sanitizeCustomListItem(it, markChanged, usedItemIds);
      if (item) items.push(item);
    }
  } else if (itemsRaw !== undefined && itemsRaw !== null) {
    markChanged();
  }

  const reminderEnabled: boolean = toBooleanOr(obj['reminderEnabled'] as Object | null | undefined, false, markChanged);
  const reminderTime: number | undefined = (() => {
    const t = toNumberOr(obj['reminderTime'] as Object | null | undefined, -1, markChanged);
    if (!Number.isFinite(t) || t < 0) return undefined;
    return clampInt(t, 0, 1439);
  })();

  return {
    id,
    name,
    description: toOptionalString(obj['description'] as Object | null | undefined, markChanged),
    icon: toOptionalString(obj['icon'] as Object | null | undefined, markChanged),
    items,
    createdAt,
    updatedAt,
    shareId: toOptionalString(obj['shareId'] as Object | null | undefined, markChanged),
    sharePassword: toOptionalString(obj['sharePassword'] as Object | null | undefined, markChanged),
    isShared: toBooleanOr(obj['isShared'] as Object | null | undefined, false, markChanged),
    sharedAt: (() => {
      const t = toNumberOr(obj['sharedAt'] as Object | null | undefined, -1, markChanged);
      return Number.isFinite(t) && t > 0 ? t : undefined;
    })(),
    calendarEventId: toOptionalString(obj['calendarEventId'] as Object | null | undefined, markChanged),
    reminderEnabled,
    reminderTime: reminderEnabled ? reminderTime : undefined,
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
 * 注：生产环境建议使用更安全的加密算法
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

/**
 * 复制CustomListItem对象
 */
function copyListItem(item: CustomListItem): CustomListItem {
  return {
    id: item.id,
    title: item.title,
    content: item.content,
    answer: item.answer,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    reviewCount: item.reviewCount,
    lastReviewAt: item.lastReviewAt,
    nextReviewAt: item.nextReviewAt,
    easeFactor: item.easeFactor,
    interval: item.interval,
    lastGrade: item.lastGrade,
  };
}

/**
 * 复制CustomList对象
 */
function copyList(list: CustomList): CustomList {
  const items: Array<CustomListItem> = [];
  for (const item of list.items) {
    items.push(copyListItem(item));
  }
  return {
    id: list.id,
    name: list.name,
    description: list.description,
    icon: list.icon,
    items: items,
    createdAt: list.createdAt,
    updatedAt: list.updatedAt,
    shareId: list.shareId,
    sharePassword: list.sharePassword,
    isShared: list.isShared,
    sharedAt: list.sharedAt,
    calendarEventId: list.calendarEventId,
    reminderEnabled: list.reminderEnabled,
    reminderTime: list.reminderTime,
  };
}

/**
 * 合并更新到CustomList
 */
function mergeListUpdates(list: CustomList, updates: Partial<CustomList>): CustomList {
  return {
    id: list.id,
    name: updates.name !== undefined ? updates.name : list.name,
    description: updates.description !== undefined ? updates.description : list.description,
    icon: updates.icon !== undefined ? updates.icon : list.icon,
    items: updates.items !== undefined ? updates.items : list.items,
    createdAt: list.createdAt,
    updatedAt: Date.now(),
    shareId: updates.shareId !== undefined ? updates.shareId : list.shareId,
    sharePassword: updates.sharePassword !== undefined ? updates.sharePassword : list.sharePassword,
    isShared: updates.isShared !== undefined ? updates.isShared : list.isShared,
    sharedAt: updates.sharedAt !== undefined ? updates.sharedAt : list.sharedAt,
    calendarEventId: updates.calendarEventId !== undefined ? updates.calendarEventId : list.calendarEventId,
    reminderEnabled: updates.reminderEnabled !== undefined ? updates.reminderEnabled : list.reminderEnabled,
    reminderTime: updates.reminderTime !== undefined ? updates.reminderTime : list.reminderTime,
  };
}

/**
 * 合并更新到CustomListItem
 */
function mergeItemUpdates(item: CustomListItem, updates: Partial<CustomListItem>): CustomListItem {
  return {
    id: item.id,
    title: updates.title !== undefined ? updates.title : item.title,
    content: updates.content !== undefined ? updates.content : item.content,
    answer: updates.answer !== undefined ? updates.answer : item.answer,
    createdAt: item.createdAt,
    updatedAt: Date.now(),
    reviewCount: updates.reviewCount !== undefined ? updates.reviewCount : item.reviewCount,
    lastReviewAt: updates.lastReviewAt !== undefined ? updates.lastReviewAt : item.lastReviewAt,
    nextReviewAt: updates.nextReviewAt !== undefined ? updates.nextReviewAt : item.nextReviewAt,
    easeFactor: updates.easeFactor !== undefined ? updates.easeFactor : item.easeFactor,
    interval: updates.interval !== undefined ? updates.interval : item.interval,
    lastGrade: updates.lastGrade !== undefined ? updates.lastGrade : item.lastGrade,
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
      // 数据损坏：避免直接崩溃导致 Tab 打开即闪退
      return createEmptyCustomListCollection();
    }

    let changed = false;
    const markChanged = (): void => {
      changed = true;
    };

    const sanitized: CustomListCollection = sanitizeCustomListCollection(parsed, markChanged);

    // 若检测到旧版本/损坏数据，则写回修复后的结构，避免后续渲染时出现字段缺失导致崩溃
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

    // 限制存储的清单数量
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
   * 添加项目到清单
   */
  async addItem(context: Context, listId: string, item: CustomListItem): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      list.items.push(item);
      list.updatedAt = Date.now();
      await this.saveCustomLists(context, collection);
    }
    return list;
  }

  /**
   * 更新清单项目
   */
  async updateItem(
    context: Context,
    listId: string,
    itemId: string,
    updates: Partial<CustomListItem>
  ): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      const itemIndex = list.items.findIndex(i => i.id === itemId);
      if (itemIndex >= 0) {
        list.items[itemIndex] = mergeItemUpdates(list.items[itemIndex], updates);
        list.updatedAt = Date.now();
        await this.saveCustomLists(context, collection);
      }
    }
    return list;
  }

  /**
   * 删除清单项目
   */
  async deleteItem(context: Context, listId: string, itemId: string): Promise<CustomList | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (list) {
      list.items = list.items.filter(i => i.id !== itemId);
      list.updatedAt = Date.now();
      await this.saveCustomLists(context, collection);
    }
    return list;
  }

  /**
   * 记录复习结果（更新艾宾浩斯记忆数据）
   */
  async recordReview(
    context: Context,
    listId: string,
    itemId: string,
    grade: ReviewGrade
  ): Promise<CustomListItem | undefined> {
    const collection = await this.getCustomLists(context);
    const list = collection.lists.find(l => l.id === listId);
    if (!list) return undefined;

    const itemIndex = list.items.findIndex(i => i.id === itemId);
    if (itemIndex < 0) return undefined;

    const updatedItem = calculateNextReview(list.items[itemIndex], grade);
    list.items[itemIndex] = updatedItem;
    list.updatedAt = Date.now();
    await this.saveCustomLists(context, collection);
    return updatedItem;
  }

  /**
   * 导出清单为分享数据（可选加密）
   */
  exportListForShare(list: CustomList, password?: string): string {
    // 创建不含敏感信息的清单副本
    const exportList: CustomList = {
      id: list.id,
      name: list.name,
      description: list.description,
      icon: list.icon,
      items: list.items,
      createdAt: list.createdAt,
      updatedAt: list.updatedAt,
      shareId: undefined,
      sharePassword: undefined,
      isShared: false,
      sharedAt: undefined,
      calendarEventId: undefined,
      reminderEnabled: false,
      reminderTime: undefined,
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
      // 加密数据
      const encrypted = encryptData(finalJson, password);
      return `ENC:${encrypted}`;
    }

    // Base64 编码（不加密）
    const base64 = new util.Base64Helper();
    const encoder = new util.TextEncoder();
    return base64.encodeToStringSync(encoder.encodeInto(finalJson));
  }

  /**
   * 导入分享数据（自动检测是否加密）
   */
  importShareData(data: string, password?: string): SharedListData | null {
    let jsonData: string = '';
    try {
      if (data.startsWith('ENC:')) {
        // 加密数据
        if (!password || password.length === 0) {
          return null; // 需要密码
        }
        const encrypted = data.slice(4);
        jsonData = decryptData(encrypted, password);
      } else {
        // Base64 编码数据
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

    // 验证数据完整性
    const checkData: SharedListData = {
      version: shareData.version,
      list: shareData.list,
      exportedAt: shareData.exportedAt,
      checksum: '',
    };
    const expectedChecksum = calculateChecksum(JSON.stringify(checkData));
    if (shareData.checksum !== expectedChecksum) {
      // 校验失败，但仍然允许导入（数据可能被手动编辑）
      console.warn('CustomListRepository: checksum mismatch');
    }

    return shareData;
  }

  /**
   * 生成分享链接
   */
  async generateShareLink(context: Context, listId: string, password?: string): Promise<string | null> {
    const list = await this.getList(context, listId);
    if (!list) return null;

    // 导出数据
    const shareData = this.exportListForShare(list, password);

    // 上传到服务器并返回短链接（支持加密：客户端先加密再上传）
    const result = await this.onlineShareRepository.createShare(shareData).then(
      (r) => r,
      () => null,
    );
    if (!result) return null;

    // 更新本地分享信息（shareId 用于标记已分享）
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

    // 1) 兼容旧格式：refhm://share/<id>?data=...
    const legacy = trimmed.match(/refhm:\/\/share\/([^?]+)\?data=(.+)/);
    if (legacy && legacy[2]) {
      const data = decodeURIComponent(legacy[2]);
      const shareData = this.importShareData(data, password);
      if (!shareData) return null;

      return await this.importSharedList(context, shareData);
    }

    // 2) 新格式：https://<host>/share/<id> 或 refhm://share/<id>
    let shareId: string = '';
    let apiOriginOverride: string = '';

    const urlMatch = trimmed.match(/^https?:\/\/([^/]+)(\/.*)?$/i);
    if (urlMatch) {
      const u = trimmed;
      const idMatch = u.match(/\/share\/([^/?#]+)/i);
      if (idMatch) {
        shareId = decodeURIComponent(idMatch[1]);
        const originMatch = u.match(/^(https?:\/\/[^/?#]+)/i);
        apiOriginOverride = originMatch ? originMatch[1] : '';
      }
    } else {
      const deepMatch = trimmed.match(/refhm:\/\/share\/([^/?#]+)/i);
      if (deepMatch) {
        shareId = decodeURIComponent(deepMatch[1]);
      }
    }

    if (!shareId) {
      // 3) 兼容：直接粘贴分享数据（Base64 或 ENC:...）
      const asData = this.importShareData(trimmed, password);
      if (!asData) return null;
      return await this.importSharedList(context, asData);
    }

    const remoteData = await this.onlineShareRepository.fetchShareData(shareId, apiOriginOverride).then(
      (d) => d,
      () => '',
    );
    if (!remoteData) return null;

    const shareData = this.importShareData(remoteData, password);
    if (!shareData) {
      return null;
    }

    return await this.importSharedList(context, shareData);
  }

  private async importSharedList(context: Context, shareData: SharedListData): Promise<CustomList | null> {
    // 创建新清单（生成新ID避免冲突）
    const now = Date.now();
    const newItems: Array<CustomListItem> = [];
    for (const item of shareData.list.items) {
      newItems.push({
        id: `item_${now}_${Math.floor(Math.random() * 10000)}_${Math.floor(Math.random() * 1000)}`,
        title: item.title,
        content: item.content,
        answer: item.answer,
        createdAt: now,
        updatedAt: now,
        reviewCount: 0,
        lastReviewAt: 0,
        nextReviewAt: now,
        easeFactor: 2.5,
        interval: 0,
        lastGrade: undefined,
      });
    }

    const newList: CustomList = {
      id: `list_${now}_${Math.floor(Math.random() * 10000)}`,
      name: shareData.list.name,
      description: shareData.list.description,
      icon: shareData.list.icon,
      items: newItems,
      createdAt: now,
      updatedAt: now,
      shareId: undefined,
      sharePassword: undefined,
      isShared: false,
      sharedAt: undefined,
      calendarEventId: undefined,
      reminderEnabled: false,
      reminderTime: undefined,
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
