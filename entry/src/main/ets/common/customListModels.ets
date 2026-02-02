// 自定义清单数据模型

/**
 * 自定义清单项目（单个卡片/知识点）
 */
export interface CustomListItem {
  id: string;
  title: string;
  content: string; // 正面内容
  answer?: string; // 背面内容（用于记忆卡片）
  createdAt: number;
  updatedAt: number;
  // 艾宾浩斯记忆相关
  reviewCount: number; // 复习次数
  lastReviewAt: number; // 上次复习时间
  nextReviewAt: number; // 下次复习时间
  easeFactor: number; // 难度系数 (默认 2.5)
  interval: number; // 当前间隔（天）
  // 复习结果：0=忘记，1=困难，2=一般，3=简单
  lastGrade?: number;
}

/**
 * 自定义清单
 */
export interface CustomList {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  items: Array<CustomListItem>;
  createdAt: number;
  updatedAt: number;
  // 分享相关
  shareId?: string; // 分享ID（用于网络分享）
  sharePassword?: string; // 分享密码（加密分享）
  isShared: boolean;
  sharedAt?: number;
  // 日历提醒
  calendarEventId?: string;
  reminderEnabled: boolean;
  reminderTime?: number; // 每日提醒时间（分钟数，如 480 = 8:00）
}

/**
 * 自定义清单集合
 */
export interface CustomListCollection {
  lists: Array<CustomList>;
  lastSyncAt: number;
}

/**
 * 艾宾浩斯记忆曲线间隔（天数）
 * 第1次复习：1天后
 * 第2次复习：2天后
 * 第3次复习：4天后
 * 第4次复习：7天后
 * 第5次复习：15天后
 * 第6次复习：30天后
 * 之后按难度系数计算
 */
export const EBBINGHAUS_INTERVALS: ReadonlyArray<number> = [1, 2, 4, 7, 15, 30];

/**
 * 复习评级
 */
export type ReviewGrade = 0 | 1 | 2 | 3;
export const REVIEW_GRADE_FORGOT: ReviewGrade = 0;
export const REVIEW_GRADE_HARD: ReviewGrade = 1;
export const REVIEW_GRADE_GOOD: ReviewGrade = 2;
export const REVIEW_GRADE_EASY: ReviewGrade = 3;

/**
 * 分享数据结构（用于导出/导入）
 */
export interface SharedListData {
  version: number;
  list: CustomList;
  exportedAt: number;
  checksum: string; // 用于验证数据完整性
}

/**
 * 待复习项目统计
 */
export interface ReviewStats {
  dueCount: number; // 今日待复习数量
  newCount: number; // 新卡片数量（未复习）
  reviewedToday: number; // 今日已复习数量
  totalItems: number; // 总卡片数
  nextReviewAt: number; // 最近的下次复习时间
}

/**
 * 创建空的自定义清单集合
 */
export function createEmptyCustomListCollection(): CustomListCollection {
  return {
    lists: [],
    lastSyncAt: 0,
  };
}

/**
 * 生成自定义清单ID
 */
export function generateCustomListId(): string {
  return `list_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

/**
 * 生成自定义清单项目ID
 */
export function generateCustomListItemId(): string {
  return `item_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

/**
 * 生成分享ID
 */
export function generateShareId(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  let result = '';
  for (let i = 0; i < 8; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

/**
 * 创建新的自定义清单
 */
export function createCustomList(name: string, description?: string): CustomList {
  const now = Date.now();
  return {
    id: generateCustomListId(),
    name,
    description,
    items: [],
    createdAt: now,
    updatedAt: now,
    isShared: false,
    reminderEnabled: false,
  };
}

/**
 * 创建新的自定义清单项目
 */
export function createCustomListItem(title: string, content: string, answer?: string): CustomListItem {
  const now = Date.now();
  return {
    id: generateCustomListItemId(),
    title,
    content,
    answer,
    createdAt: now,
    updatedAt: now,
    reviewCount: 0,
    lastReviewAt: 0,
    nextReviewAt: now, // 立即可复习
    easeFactor: 2.5,
    interval: 0,
  };
}

/**
 * 根据艾宾浩斯记忆曲线计算下次复习时间
 * @param item 清单项目
 * @param grade 复习评级 (0-3)
 * @returns 更新后的项目
 */
export function calculateNextReview(item: CustomListItem, grade: ReviewGrade): CustomListItem {
  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;
  
  let newInterval: number;
  let newEaseFactor = item.easeFactor;
  
  if (grade === REVIEW_GRADE_FORGOT) {
    // 忘记了，重置间隔
    newInterval = 1;
    newEaseFactor = Math.max(1.3, item.easeFactor - 0.2);
  } else if (item.reviewCount < EBBINGHAUS_INTERVALS.length) {
    // 使用艾宾浩斯预设间隔
    newInterval = EBBINGHAUS_INTERVALS[item.reviewCount];
    
    // 根据评级微调
    if (grade === REVIEW_GRADE_HARD) {
      newInterval = Math.max(1, Math.floor(newInterval * 0.8));
      newEaseFactor = Math.max(1.3, item.easeFactor - 0.15);
    } else if (grade === REVIEW_GRADE_EASY) {
      newInterval = Math.floor(newInterval * 1.3);
      newEaseFactor = Math.min(3.0, item.easeFactor + 0.15);
    }
  } else {
    // 使用 SM-2 算法计算
    newInterval = Math.round(item.interval * item.easeFactor);
    
    // 根据评级调整难度系数
    newEaseFactor = item.easeFactor + (0.1 - (3 - grade) * (0.08 + (3 - grade) * 0.02));
    newEaseFactor = Math.max(1.3, Math.min(3.0, newEaseFactor));
    
    if (grade === REVIEW_GRADE_HARD) {
      newInterval = Math.max(1, Math.floor(newInterval * 0.8));
    } else if (grade === REVIEW_GRADE_EASY) {
      newInterval = Math.floor(newInterval * 1.3);
    }
  }
  
  const result: CustomListItem = {
    id: item.id,
    title: item.title,
    content: item.content,
    answer: item.answer,
    createdAt: item.createdAt,
    updatedAt: now,
    reviewCount: item.reviewCount + 1,
    lastReviewAt: now,
    nextReviewAt: now + newInterval * dayMs,
    easeFactor: newEaseFactor,
    interval: newInterval,
    lastGrade: grade,
  };
  return result;
}

/**
 * 获取待复习的项目
 */
export function getDueItems(items: Array<CustomListItem>): Array<CustomListItem> {
  const now = Date.now();
  return items.filter(item => item.nextReviewAt <= now);
}

/**
 * 计算复习统计
 */
export function calculateReviewStats(items: Array<CustomListItem>): ReviewStats {
  const now = Date.now();
  const todayStart = new Date().setHours(0, 0, 0, 0);
  const todayEnd = todayStart + 24 * 60 * 60 * 1000;
  
  let dueCount = 0;
  let newCount = 0;
  let reviewedToday = 0;
  let nextReviewAt = Number.MAX_SAFE_INTEGER;
  
  for (const item of items) {
    if (item.reviewCount === 0) {
      newCount++;
    }
    
    if (item.nextReviewAt <= now) {
      dueCount++;
    } else if (item.nextReviewAt < nextReviewAt) {
      nextReviewAt = item.nextReviewAt;
    }
    
    if (item.lastReviewAt >= todayStart && item.lastReviewAt < todayEnd) {
      reviewedToday++;
    }
  }
  
  return {
    dueCount,
    newCount,
    reviewedToday,
    totalItems: items.length,
    nextReviewAt: nextReviewAt === Number.MAX_SAFE_INTEGER ? 0 : nextReviewAt,
  };
}

/**
 * 简单的校验和计算
 */
export function calculateChecksum(data: string): string {
  let hash = 0;
  for (let i = 0; i < data.length; i++) {
    const char = data.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // 转换为32位整数
  }
  return Math.abs(hash).toString(16).padStart(8, '0');
}
