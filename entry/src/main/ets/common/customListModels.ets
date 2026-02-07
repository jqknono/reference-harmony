// 自定义清单数据模型 - 记忆表格模式

/**
 * 表格单元格
 */
export interface MemoryTableCell {
  text: string;
}

/**
 * 表格行
 */
export interface MemoryTableRow {
  id: string;
  cells: Array<MemoryTableCell>;
  // 艾宾浩斯记忆相关（每行独立追踪）
  reviewCount: number;
  lastReviewAt: number;
  nextReviewAt: number;
  easeFactor: number;
  interval: number;
  lastGrade?: number;
}

/**
 * 记忆表格
 */
export interface MemoryTable {
  id: string;
  headers: Array<string>; // 表头
  rows: Array<MemoryTableRow>;
  createdAt: number;
  updatedAt: number;
}

/**
 * 清单章节（对应markdown的header）
 */
export interface ListSection {
  id: string;
  level: number; // 1-6 对应 # 到 ######
  title: string;
  content: string; // 章节描述文本
  tables: Array<MemoryTable>; // 该章节下的表格
  createdAt: number;
  updatedAt: number;
}

/**
 * 自定义清单（记忆表格模式）
 */
export interface CustomList {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  sections: Array<ListSection>;
  createdAt: number;
  updatedAt: number;
  // 分享相关
  shareId?: string;
  sharePassword?: string;
  isShared: boolean;
  sharedAt?: number;
  // 日历提醒
  calendarEventId?: string;
  reminderEnabled: boolean;
  reminderTime?: number;
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
  checksum: string;
}

/**
 * 待复习项目统计
 */
export interface ReviewStats {
  dueCount: number;
  newCount: number;
  reviewedToday: number;
  totalRows: number;
  nextReviewAt: number;
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
 * 生成ID
 */
export function generateId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

export function generateCustomListId(): string {
  return generateId('list');
}

export function generateSectionId(): string {
  return generateId('sec');
}

export function generateTableId(): string {
  return generateId('tbl');
}

export function generateRowId(): string {
  return generateId('row');
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
 * 创建新的表格行
 */
export function createTableRow(cells: Array<string>): MemoryTableRow {
  const now = Date.now();
  const cellObjs: Array<MemoryTableCell> = [];
  for (const text of cells) {
    cellObjs.push({ text });
  }
  return {
    id: generateRowId(),
    cells: cellObjs,
    reviewCount: 0,
    lastReviewAt: 0,
    nextReviewAt: now,
    easeFactor: 2.5,
    interval: 0,
  };
}

/**
 * 创建新的表格
 */
export function createMemoryTable(headers: Array<string>): MemoryTable {
  const now = Date.now();
  return {
    id: generateTableId(),
    headers: headers.length > 0 ? headers : ['', ''],
    rows: [],
    createdAt: now,
    updatedAt: now,
  };
}

/**
 * 创建新的章节
 */
export function createListSection(title: string, level: number = 2): ListSection {
  const now = Date.now();
  return {
    id: generateSectionId(),
    level: Math.max(1, Math.min(6, level)),
    title,
    content: '',
    tables: [],
    createdAt: now,
    updatedAt: now,
  };
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
    sections: [],
    createdAt: now,
    updatedAt: now,
    isShared: false,
    reminderEnabled: false,
  };
}

/**
 * 根据艾宾浩斯记忆曲线计算下次复习时间
 */
export function calculateNextReview(row: MemoryTableRow, grade: ReviewGrade): MemoryTableRow {
  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;

  let newInterval: number;
  let newEaseFactor = row.easeFactor;

  if (grade === REVIEW_GRADE_FORGOT) {
    newInterval = 1;
    newEaseFactor = Math.max(1.3, row.easeFactor - 0.2);
  } else if (row.reviewCount < EBBINGHAUS_INTERVALS.length) {
    newInterval = EBBINGHAUS_INTERVALS[row.reviewCount];

    if (grade === REVIEW_GRADE_HARD) {
      newInterval = Math.max(1, Math.floor(newInterval * 0.8));
      newEaseFactor = Math.max(1.3, row.easeFactor - 0.15);
    } else if (grade === REVIEW_GRADE_EASY) {
      newInterval = Math.floor(newInterval * 1.3);
      newEaseFactor = Math.min(3.0, row.easeFactor + 0.15);
    }
  } else {
    newInterval = Math.round(row.interval * row.easeFactor);

    newEaseFactor = row.easeFactor + (0.1 - (3 - grade) * (0.08 + (3 - grade) * 0.02));
    newEaseFactor = Math.max(1.3, Math.min(3.0, newEaseFactor));

    if (grade === REVIEW_GRADE_HARD) {
      newInterval = Math.max(1, Math.floor(newInterval * 0.8));
    } else if (grade === REVIEW_GRADE_EASY) {
      newInterval = Math.floor(newInterval * 1.3);
    }
  }

  const newCells: Array<MemoryTableCell> = [];
  for (const cell of row.cells) {
    newCells.push({ text: cell.text });
  }

  return {
    id: row.id,
    cells: newCells,
    reviewCount: row.reviewCount + 1,
    lastReviewAt: now,
    nextReviewAt: now + newInterval * dayMs,
    easeFactor: newEaseFactor,
    interval: newInterval,
    lastGrade: grade,
  };
}

/**
 * 获取所有待复习的行
 */
export interface DueRowItem {
  sectionId: string;
  tableId: string;
  row: MemoryTableRow;
}

export function getDueRows(list: CustomList): Array<DueRowItem> {
  const now = Date.now();
  const result: Array<DueRowItem> = [];

  for (const section of list.sections) {
    for (const table of section.tables) {
      for (const row of table.rows) {
        if (row.nextReviewAt <= now) {
          result.push({ sectionId: section.id, tableId: table.id, row: row });
        }
      }
    }
  }

  return result;
}

/**
 * 计算复习统计
 */
export function calculateReviewStats(list: CustomList): ReviewStats {
  const now = Date.now();
  const todayStart = new Date().setHours(0, 0, 0, 0);
  const todayEnd = todayStart + 24 * 60 * 60 * 1000;

  let dueCount = 0;
  let newCount = 0;
  let reviewedToday = 0;
  let totalRows = 0;
  let nextReviewAt = Number.MAX_SAFE_INTEGER;

  for (const section of list.sections) {
    for (const table of section.tables) {
      for (const row of table.rows) {
        totalRows++;

        if (row.reviewCount === 0) {
          newCount++;
        }

        if (row.nextReviewAt <= now) {
          dueCount++;
        } else if (row.nextReviewAt < nextReviewAt) {
          nextReviewAt = row.nextReviewAt;
        }

        if (row.lastReviewAt >= todayStart && row.lastReviewAt < todayEnd) {
          reviewedToday++;
        }
      }
    }
  }

  return {
    dueCount,
    newCount,
    reviewedToday,
    totalRows,
    nextReviewAt: nextReviewAt === Number.MAX_SAFE_INTEGER ? 0 : nextReviewAt,
  };
}

/**
 * 将清单转换为Markdown格式
 */
export function listToMarkdown(list: CustomList): string {
  const lines: Array<string> = [];

  // 标题
  lines.push(`# ${list.name}`);
  lines.push('');

  // 描述
  if (list.description) {
    lines.push(list.description);
    lines.push('');
  }

  // 章节
  for (const section of list.sections) {
    // 章节标题
    const prefix = '#'.repeat(section.level);
    lines.push(`${prefix} ${section.title}`);
    lines.push('');

    // 章节描述
    if (section.content) {
      lines.push(section.content);
      lines.push('');
    }

    // 表格
    for (const table of section.tables) {
      if (table.headers.length === 0) continue;

      // 表头
      lines.push('| ' + table.headers.join(' | ') + ' |');

      // 分隔符
      const separators: Array<string> = [];
      for (let i = 0; i < table.headers.length; i++) {
        separators.push('---');
      }
      lines.push('| ' + separators.join(' | ') + ' |');

      // 数据行
      for (const row of table.rows) {
        const cells: Array<string> = [];
        for (let i = 0; i < table.headers.length; i++) {
          const cell = row.cells[i];
          // 转义 | 字符
          const text = cell ? cell.text.replace(/\|/g, '\\|').replace(/\n/g, '<br>') : '';
          cells.push(text);
        }
        lines.push('| ' + cells.join(' | ') + ' |');
      }

      lines.push('');
    }
  }

  return lines.join('\n');
}

/**
 * 从Markdown解析清单
 */
export function markdownToList(markdown: string, existingId?: string): CustomList {
  const now = Date.now();
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');

  let name = '';
  let description = '';
  const sections: Array<ListSection> = [];
  let currentSection: ListSection | null = null;
  let currentTable: MemoryTable | null = null;
  let inTable = false;
  let tableHeaderParsed = false;

  const finalizeTable = (): void => {
    if (currentTable && currentSection) {
      currentSection.tables.push(currentTable);
      currentTable = null;
    }
    inTable = false;
    tableHeaderParsed = false;
  };

  const finalizeSection = (): void => {
    finalizeTable();
    if (currentSection) {
      sections.push(currentSection);
      currentSection = null;
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // 检测标题
    const headingMatch = /^(#{1,6})\s+(.+)$/.exec(trimmed);
    if (headingMatch) {
      const level = headingMatch[1].length;
      const title = headingMatch[2].trim();

      if (level === 1 && !name) {
        // 文档标题
        name = title;
      } else {
        // 章节标题
        finalizeSection();
        currentSection = createListSection(title, level);
      }
      continue;
    }

    // 检测表格
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      const cells = splitTableLine(trimmed);

      if (!inTable) {
        // 可能是表头
        inTable = true;
        tableHeaderParsed = false;
        currentTable = createMemoryTable(cells);
        continue;
      }

      if (!tableHeaderParsed) {
        // 分隔符行
        if (isTableSeparator(trimmed)) {
          tableHeaderParsed = true;
          continue;
        } else {
          // 不是有效表格
          finalizeTable();
          continue;
        }
      }

      // 数据行
      if (currentTable) {
        const row = createTableRow(cells);
        currentTable.rows.push(row);
      }
      continue;
    }

    // 非表格行
    if (inTable) {
      finalizeTable();
    }

    // 空行
    if (!trimmed) {
      continue;
    }

    // 普通文本
    if (!name) {
      name = trimmed;
    } else if (!currentSection) {
      // 文档描述
      if (description) {
        description += '\n' + trimmed;
      } else {
        description = trimmed;
      }
    } else {
      // 章节内容
      if (currentSection.content) {
        currentSection.content += '\n' + trimmed;
      } else {
        currentSection.content = trimmed;
      }
    }
  }

  finalizeSection();

  return {
    id: existingId || generateCustomListId(),
    name: name || 'Untitled',
    description: description || undefined,
    sections,
    createdAt: now,
    updatedAt: now,
    isShared: false,
    reminderEnabled: false,
  };
}

/**
 * 分割表格行
 */
function splitTableLine(line: string): Array<string> {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);

  const cells: Array<string> = [];
  let current = '';
  let escaped = false;

  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);

    if (escaped) {
      current += ch;
      escaped = false;
      continue;
    }

    if (ch === '\\') {
      escaped = true;
      continue;
    }

    if (ch === '|') {
      cells.push(current.trim().replace(/<br>/gi, '\n'));
      current = '';
      continue;
    }

    current += ch;
  }

  cells.push(current.trim().replace(/<br>/gi, '\n'));
  return cells;
}

/**
 * 检测是否为表格分隔符行
 */
function isTableSeparator(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed.includes('|')) return false;

  let s = trimmed;
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);

  const cells = s.split('|');
  for (const cell of cells) {
    const c = cell.trim();
    if (!/^:?-{3,}:?$/.test(c)) return false;
  }
  return cells.length > 0;
}

/**
 * 简单的校验和计算
 */
export function calculateChecksum(data: string): string {
  let hash = 0;
  for (let i = 0; i < data.length; i++) {
    const char = data.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, '0');
}
