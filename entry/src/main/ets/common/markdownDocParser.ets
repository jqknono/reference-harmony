/**
 * Markdown -> ReferenceDoc 解析器（用于在线/本地用户 Markdown）
 *
 * 注意：本文件解析规则需要与 `tools/sync_reference_docs.mjs` 中的 `parseMarkdownToCards` 保持一致，
 * 避免线上解析与离线 rawfile 产物出现卡片/分区行为差异。
 */
import type { ReferenceDoc, ReferenceSection, ReferenceCardData, ReferenceDocSource } from './referenceModels';

function cleanHeadingText(text: string): string {
  return text.replace(/\\<\s*\/\s*>\s*/g, '').replace(/\s*\{[^}]*\}\s*$/, '').trim();
}

function stripHtmlCommentsInLine(line: string): string {
  // 移除 HTML 注释（含 rehype 指令），例如: <!-- ... -->
  // 仅用于普通文本行；代码围栏内部的内容会被整体保留。
  return String(line ?? '').replace(/<!--[\s\S]*?-->/g, '');
}

function isProbablyAutolinkInner(inner: string): boolean {
  const s = String(inner ?? '').trim();
  if (!s) return false;
  if (/\s/.test(s)) return false;
  if (/^(https?:\/\/|mailto:|tel:)/i.test(s)) return true;
  // email autolink: <user@example.com>
  if (s.includes('@') && /^[^@]+@[^@]+\.[^@]+$/.test(s)) return true;
  return false;
}

export function stripTagsInLine(line: string): string {
  // 剥离任意 `<tag ...>` / `</tag>`，保留内部文本。
  // 重要：避免误伤
  // - 行内代码（反引号包裹）里的 `<...>`
  // - 被反斜杠转义的 `\<...>`（通常用于展示字面量 `<tag>`）
  // - Markdown autolink：`<https://...>` / `<mailto:...>` / `<user@a.b>`（保留内容，去掉尖括号）
  // - `<br>` / `<br/>` / `<br />` 视为硬换行：转为字面量 "\\n"（两字符），避免表格按 '\n' 分行解析被破坏
  const s = String(line ?? '');
  let out = '';
  let inInlineCode = false;
  let inlineFenceLen = 0;

  const countBackticksAt = (idx: number): number => {
    let n = 0;
    while (idx + n < s.length && s.charAt(idx + n) === '`') n++;
    return n;
  };

  const isEscapedByBackslashes = (idx: number): boolean => {
    let n = 0;
    for (let j = idx - 1; j >= 0 && s.charAt(j) === '\\'; j--) n++;
    return n % 2 === 1;
  };

  const findClosingBacktickRun = (fromIdx: number, fenceLen: number): number => {
    for (let j = fromIdx; j < s.length; j++) {
      if (s.charAt(j) !== '`') continue;
      const run = countBackticksAt(j);
      if (run === fenceLen) return j;
      j += run - 1;
    }
    return -1;
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);

    if (ch === '`') {
      const run = countBackticksAt(i);
      const escaped = isEscapedByBackslashes(i);
      if (!inInlineCode) {
        if (!escaped) {
          const close = findClosingBacktickRun(i + run, run);
          if (close !== -1) {
            inInlineCode = true;
            inlineFenceLen = run;
          }
        }
      } else if (run === inlineFenceLen) {
        // 代码段内不处理反斜杠转义：反斜杠属于内容，不影响闭合
        inInlineCode = false;
        inlineFenceLen = 0;
      }
      out += '`'.repeat(run);
      i += run - 1;
      continue;
    }

    if (!inInlineCode) {
      if (ch === '\\' && i + 1 < s.length && s.charAt(i + 1) === '<') {
        out += ch;
        out += '<';
        i += 1;
        continue;
      }
      if (ch === '<') {
        const end = s.indexOf('>', i + 1);
        if (end === -1) {
          out += ch;
          continue;
        }
        const inner = s.slice(i + 1, end);
        const lowerInner = inner.trim().toLowerCase();
        if (lowerInner.startsWith('br') && (lowerInner.length === 2 || /^[\s/]/.test(lowerInner.slice(2)))) {
          out += '\\n';
          i = end;
          continue;
        }
        if (isProbablyAutolinkInner(inner)) {
          out += inner.trim();
          i = end;
          continue;
        }
        // 仅当 `<` 后不是空白时，才视为 tag（避免误伤 "a < b" 之类）
        const first = inner.charAt(0);
        if (first && !/\s/.test(first)) {
          // Drop the whole tag token: <...>
          i = end;
          continue;
        }
        out += ch;
        continue;
      }
    }
    out += ch;
  }
  return out;
}

function splitTableRow(line: string): Array<string> {
  // Markdown 表格行解析：
  // - `\|` 表示单元格内的字面量 `|`，不应当作为分隔符
  // - 行内代码（反引号包裹）中的 `|` 也不应当作为分隔符
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);

  const cells: Array<string> = [];
  let current = '';
  let inInlineCode = false;

  const isEscapedByBackslashes = (idx: number): boolean => {
    let n = 0;
    for (let j = idx - 1; j >= 0 && s.charAt(j) === '\\'; j--) n++;
    return n % 2 === 1;
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);

    // 处理转义：\| -> |
    if (ch === '\\' && i + 1 < s.length) {
      const next = s.charAt(i + 1);
      if (next === '|') {
        current += '|';
        i += 1;
        continue;
      }
      current += ch;
      continue;
    }

    // 行内代码切换（简单支持：单个反引号）
    if (ch === '`') {
      if (inInlineCode) {
        // 代码段内不处理反斜杠转义：反斜杠属于内容，不影响闭合
        inInlineCode = false;
      } else {
        const escaped = isEscapedByBackslashes(i);
        const hasClose = s.indexOf('`', i + 1) >= 0;
        if (!escaped && hasClose) {
          inInlineCode = true;
        }
      }
      current += ch;
      continue;
    }

    // 列分隔符：不在行内代码内时生效
    if (ch === '|' && !inInlineCode) {
      cells.push(current.trim());
      current = '';
      continue;
    }

    current += ch;
  }

  cells.push(current.trim());
  return cells;
}

function isTableSeparatorLine(line: string): boolean {
  // | --- | :---: | ---: |
  // 与 tools/sync_reference_docs.mjs 保持一致：允许单列表格；单元必须为 :?-{3,}:?
  const trimmed = stripHtmlCommentsInLine(line).trim();
  if (!trimmed.includes('|')) return false;
  // 快速拒绝：分隔行只能由管道、冒号、短横线、空白组成
  if (/[^|\s:-]/.test(trimmed)) return false;

  const cells = splitTableRow(trimmed);
  if (cells.length === 0) return false;
  for (let i = 0; i < cells.length; i++) {
    const c = cells[i].replace(/\s+/g, '');
    if (!/^:?-{3,}:?$/.test(c)) return false;
  }
  return true;
}

function isListItem(line: string): boolean {
  return /^\s*([-*+]|(\d+\.))\s+/.test(line);
}

function stripListMarker(line: string): string {
  return line.replace(/^\s*([-*+]|(\d+\.))\s+/, '').trim();
}

interface FenceInfo {
  marker: string;
  lang: string;
  info: string;
}

function parseFenceOpen(line: string): FenceInfo | undefined {
  const m = /^\s*(`{3,}|~{3,})\s*([^\n]*)$/.exec(line);
  if (!m) return undefined;
  const info = String(m[2] ?? '').trim();
  const lang = info.split(/\s+/)[0] ?? '';
  const result: FenceInfo = { marker: m[1], lang: lang, info: info };
  return result;
}

function isFenceClose(line: string, marker: string): boolean {
  const t = String(line ?? '').trim();
  if (!t) return false;
  const ch = marker[0];
  if (t.length < marker.length) return false;
  for (let i = 0; i < t.length; i++) {
    if (t[i] !== ch) return false;
  }
  return true;
}

function isRehypeIgnoreStart(line: string): boolean {
  return /^\s*<!--\s*rehype:ignore:start\s*-->\s*$/.test(line);
}

function isRehypeIgnoreEnd(line: string): boolean {
  return /^\s*<!--\s*rehype:ignore:end\s*-->\s*$/.test(line);
}

function isHtmlPreviewFence(fence: FenceInfo | undefined): boolean {
  const info = String(fence?.info ?? '').trim().toLowerCase();
  return /^html\s+preview(\s|$)/.test(info);
}

function isHorizontalRuleLine(line: string): boolean {
  const t = (line ?? '').trim();
  if (!t) return false;
  return /^(-{3,}|\*{3,}|_{3,})$/.test(t);
}

function isSetextUnderline(line: string, ch?: string): boolean {
  const t = line.trim();
  if (!t) return false;
  if (ch) {
    const escaped = ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(`^${escaped}{3,}$`).test(t);
  }
  return /^={3,}$/.test(t) || /^-{3,}$/.test(t);
}

interface SetextHeadingInfo {
  level: number;
  text: string;
}

function getSetextHeading(lines: Array<string>, i: number): SetextHeadingInfo | undefined {
  if (i + 1 >= lines.length) return undefined;
  const text = stripHtmlCommentsInLine(lines[i] ?? '').trim();
  if (!text) return undefined;
  const underline = stripHtmlCommentsInLine(lines[i + 1] ?? '').trim();
  if (isSetextUnderline(underline, '=')) {
    const result: SetextHeadingInfo = { level: 1, text: text };
    return result;
  }
  if (isSetextUnderline(underline, '-')) {
    const result: SetextHeadingInfo = { level: 2, text: text };
    return result;
  }
  return undefined;
}

interface Frontmatter {
  title?: string;
  intro?: string;
  icon?: string;
  background?: string;
}

interface FrontmatterExtractResult {
  frontmatter: Frontmatter;
  body: string;
}

function extractFrontmatter(markdown: string): FrontmatterExtractResult {
  const normalized = markdown.replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) {
    const emptyFm: Frontmatter = {};
    const result: FrontmatterExtractResult = { frontmatter: emptyFm, body: normalized };
    return result;
  }
  const end = normalized.indexOf('\n---\n', 4);
  if (end === -1) {
    const emptyFm: Frontmatter = {};
    const result: FrontmatterExtractResult = { frontmatter: emptyFm, body: normalized };
    return result;
  }
  const block = normalized.slice(4, end);
  const body = normalized.slice(end + '\n---\n'.length);

  const frontmatter: Frontmatter = {};
  const lines = block.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!m) continue;
    const key = m[1];
    const rawValue = (m[2] ?? '').trim();

    if (key === 'title') {
      frontmatter.title = rawValue.replace(/^['"]|['"]$/g, '').trim();
      continue;
    }

    if (key === 'intro') {
      if (rawValue === '|' || rawValue === '>') {
        const buf: Array<string> = [];
        i++;
        while (i < lines.length) {
          const l = lines[i];
          if (!/^\s{2,}\S/.test(l) && l.trim() !== '') break;
          buf.push(l.replace(/^\s{2}/, ''));
          i++;
        }
        i--;
        frontmatter.intro = buf.join('\n').trim();
      } else {
        frontmatter.intro = rawValue.replace(/^['"]|['"]$/g, '').trim();
      }
    }

    if (key === 'icon') {
      frontmatter.icon = rawValue.replace(/^['"]|['"]$/g, '').trim();
    }

    if (key === 'background') {
      frontmatter.background = rawValue.replace(/^['"]|['"]$/g, '').trim();
    }
  }

  const result: FrontmatterExtractResult = { frontmatter: frontmatter, body: body };
  return result;
}

interface DocNameAndTitle {
  name: string;
  title: string;
}

function extractDocNameAndTitle(frontmatter: Frontmatter, body: string, id: string): DocNameAndTitle {
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const frontName = (frontmatter.title ?? '').trim();
  const frontIntro = (frontmatter.intro ?? '').trim();
  if (frontName) {
    const result: DocNameAndTitle = { name: frontName, title: frontIntro || frontName };
    return result;
  }

  let name = id;
  let title = '';
  let h1Index = -1;
  let h1IsSetext = false;
  let rehypeIgnoreDepth = 0;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    if (!rawLine) continue;
    if (isRehypeIgnoreStart(rawLine)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(rawLine)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    const line = stripHtmlCommentsInLine(rawLine);
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), fence.marker)) i++;
      continue;
    }

    const setext = getSetextHeading(lines, i);
    if (setext?.level === 1) {
      name = cleanHeadingText(setext.text);
      h1Index = i;
      h1IsSetext = true;
      break;
    }

    const atx1 = /^#\s+(.+)$/.exec(line);
    if (atx1) {
      name = cleanHeadingText(atx1[1].trim());
      h1Index = i;
      break;
    }
  }

  const start = h1Index === -1 ? 0 : (h1IsSetext ? h1Index + 2 : h1Index + 1);
  for (let i = start; i < lines.length; i++) {
    const rawLine = lines[i];
    if (!rawLine) continue;
    if (isRehypeIgnoreStart(rawLine)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(rawLine)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    const line = stripHtmlCommentsInLine(rawLine);
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;

    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), fence.marker)) i++;
      continue;
    }

    const setext = getSetextHeading(lines, i);
    if (setext?.level === 2) break;
    if (/^##\s+/.test(line)) break;

    if (/^#{1,6}\s+/.test(line)) continue;
    if (isSetextUnderline(line)) continue;
    const t = line.trim();
    if (t) {
      title = t;
      break;
    }
  }

  const result: DocNameAndTitle = { name: name, title: title || name };
  return result;
}

interface CardRaw {
  id: string;
  sectionId: string;
  title: string;
  body?: string;
  lang?: string;
  encoded?: boolean;
}

export function parseMarkdownToDoc(markdown: string, id: string, url: string, keepTags: boolean = false): ReferenceDoc {
  const fmResult = extractFrontmatter(markdown);
  const frontmatter = fmResult.frontmatter;
  const body = fmResult.body;
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const meta = extractDocNameAndTitle(frontmatter, body, id);
  const title = meta.title;
  const name = meta.name;
  const introTitle = '简介';

  const normalizeLine = (raw: string): string => {
    const withoutComments = stripHtmlCommentsInLine(raw);
    if (keepTags) return withoutComments;
    return stripTagsInLine(withoutComments);
  };

  const introSection: ReferenceSection = { id: 'intro', title: introTitle, startIndex: 0 };
  const sections: Array<ReferenceSection> = [introSection];
  const cards: Array<CardRaw> = [];

  let currentSectionId = 'intro';
  let currentSectionTitle = introTitle;
  let lastH3 = '';
  let lastH4 = '';
  let h3TitleUsed = false;
  let h4TitleUsed = false;
  let consumedDocHeading = false;

  const resetHeadingState = (): void => {
    lastH3 = '';
    lastH4 = '';
    h3TitleUsed = false;
    h4TitleUsed = false;
  };

  const setH3 = (titleText: string): void => {
    lastH3 = titleText;
    lastH4 = '';
    h3TitleUsed = false;
    h4TitleUsed = false;
  };

  const setH4 = (titleText: string): void => {
    lastH4 = titleText;
    h4TitleUsed = false;
  };

  const nextCardTitle = (): string => {
    if (currentSectionId === 'intro') return currentSectionTitle;
    if (lastH4 && lastH3 && !h3TitleUsed) {
      h3TitleUsed = true;
      h4TitleUsed = true;
      return `${lastH3} - ${lastH4}`;
    }
    if (lastH4) {
      if (!h4TitleUsed) {
        h4TitleUsed = true;
        return lastH4;
      }
      return '';
    }
    if (lastH3) {
      if (!h3TitleUsed) {
        h3TitleUsed = true;
        return lastH3;
      }
      return '';
    }
    return currentSectionTitle;
  };

  const pushCard = (card: CardRaw): void => {
    const allText = [card.title ?? '', card.body ?? ''].join('\n');
    const needsEncoding = allText.includes('"') || allText.includes("'");
    if (!needsEncoding) {
      cards.push(card);
      return;
    }
    const encodedCard: CardRaw = {
      id: card.id,
      sectionId: card.sectionId,
      title: encodeURIComponent(card.title),
      body: card.body ? encodeURIComponent(card.body) : undefined,
      lang: card.lang,
      encoded: true,
    };
    cards.push(encodedCard);
  };

  const intro = (frontmatter.intro ?? '').trim();
  if (intro) {
    const introCard: CardRaw = {
      id: `${currentSectionId}-${cards.length}`,
      sectionId: currentSectionId,
      title: nextCardTitle(),
      body: intro,
    };
    pushCard(introCard);
  }

  let rehypeIgnoreDepth = 0;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const line = normalizeLine(rawLine);
    if (isRehypeIgnoreStart(rawLine)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(rawLine)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (isHorizontalRuleLine(line)) continue;

    const setext = getSetextHeading(lines, i);
    if (setext) {
      if (setext.level === 1) {
        consumedDocHeading = true;
        resetHeadingState();
      } else {
        currentSectionTitle = cleanHeadingText(setext.text);
        currentSectionId = `s${sections.length}`;
        const newSection: ReferenceSection = { id: currentSectionId, title: currentSectionTitle, startIndex: cards.length };
        sections.push(newSection);
        resetHeadingState();
      }
      i++;
      continue;
    }

    const h1 = /^#\s+(.+)$/.exec(line);
    if (h1) {
      const hText = cleanHeadingText(h1[1].trim());
      if (!consumedDocHeading) {
        consumedDocHeading = true;
        resetHeadingState();
        continue;
      }
      currentSectionTitle = hText;
      currentSectionId = `s${sections.length}`;
      const newSection1: ReferenceSection = { id: currentSectionId, title: currentSectionTitle, startIndex: cards.length };
      sections.push(newSection1);
      resetHeadingState();
      continue;
    }

    const h2 = /^##\s+(.+)$/.exec(line);
    if (h2) {
      currentSectionTitle = cleanHeadingText(h2[1].trim());
      currentSectionId = `s${sections.length}`;
      const newSection2: ReferenceSection = { id: currentSectionId, title: currentSectionTitle, startIndex: cards.length };
      sections.push(newSection2);
      resetHeadingState();
      continue;
    }

    const h3 = /^###\s+(.+)$/.exec(line);
    if (h3) {
      setH3(cleanHeadingText(h3[1].trim()));
      continue;
    }

    const h4 = /^####\s+(.+)$/.exec(line);
    if (h4) {
      setH4(cleanHeadingText(h4[1].trim()));
      continue;
    }

    const fence = parseFenceOpen(line);
    if (fence) {
      if (isHtmlPreviewFence(fence)) {
        i++;
        while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), fence.marker)) i++;
        continue;
      }
      const codeParts: Array<string> = [];

      const skipBetweenFences = (l: string): boolean => {
        // 不要跨越 ignore 标记；外层循环需要正确维护 ignore 区域状态
        if (isRehypeIgnoreStart(l) || isRehypeIgnoreEnd(l)) return false;
        const cleaned = stripHtmlCommentsInLine(l);
        if (!cleaned.trim()) return true;
        if (/^\s*\{[.#][^}]+\}\s*$/.test(cleaned)) return true;
        if (isHorizontalRuleLine(cleaned)) return true;
        return false;
      };

      while (i < lines.length) {
        const openFence = parseFenceOpen(stripHtmlCommentsInLine(lines[i]));
        if (!openFence) break;
        const fenceOpenLine = stripHtmlCommentsInLine(lines[i]);
        const buf: Array<string> = [];
        i++;
        while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), openFence.marker)) {
          buf.push(lines[i]);
          i++;
        }
        const fenceCloseLine = i < lines.length ? stripHtmlCommentsInLine(lines[i]) : openFence.marker;
        const codeBlock = `${fenceOpenLine}\n${buf.join('\n')}\n${fenceCloseLine}`;
        codeParts.push(codeBlock);

        let j = i + 1;
        while (j < lines.length && skipBetweenFences(lines[j])) j++;
        const nextFence = j < lines.length ? parseFenceOpen(stripHtmlCommentsInLine(lines[j])) : undefined;
        if (!nextFence || isHtmlPreviewFence(nextFence)) break;

        i = j;
      }

      const mergedCode = codeParts.join('\n\n').trimEnd();
      if (mergedCode) {
        const codeCard: CardRaw = {
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          body: mergedCode,
        };
        pushCard(codeCard);
      }
      continue;
    }

    if (line.includes('|') && i + 1 < lines.length && isTableSeparatorLine(lines[i + 1])) {
      const buf = [line.trimEnd(), normalizeLine(lines[i + 1]).trimEnd()];
      i += 2;
      while (i < lines.length) {
        const rowLine = normalizeLine(lines[i]);
        if (!rowLine.trim() || !rowLine.includes('|')) break;
        buf.push(rowLine.trimEnd());
        i++;
      }
      i--;
      const bodyText = buf.join('\n').trimEnd();
      if (bodyText) {
        const tableCard: CardRaw = {
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          body: bodyText,
        };
        pushCard(tableCard);
      }
      continue;
    }

    if (isListItem(line)) {
      const items: Array<string> = [];
      while (i < lines.length) {
        const itemLine = normalizeLine(lines[i]);
        if (!isListItem(itemLine)) break;
        const itemText = stripListMarker(itemLine);
        if (itemText) items.push(`• ${itemText}`);
        i++;
      }
      i--;
      const text = items.join('\n').trim();
      if (text) {
        const listCard: CardRaw = {
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          body: text,
        };
        pushCard(listCard);
      }
      continue;
    }

    if (line.trim()) {
      const buf = [line.trim()];
      i++;
      while (i < lines.length) {
        const nextLine = normalizeLine(lines[i]);
        if (!nextLine.trim()) break;
        if (getSetextHeading(lines, i)) break;
        if (/^#{1,6}\s+/.test(nextLine)) break;
        if (isListItem(nextLine)) break;
        if (parseFenceOpen(nextLine)) break;
        if (isHorizontalRuleLine(nextLine)) break;
        if (!/^\s*\{[.#][^}]+\}\s*$/.test(nextLine)) buf.push(nextLine.trim());
        i++;
      }
      i--;
      const text = buf.join('\n').trim();
      if (text) {
        const textCard: CardRaw = {
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          body: text,
        };
        pushCard(textCard);
      }
    }
  }

  const decodeIfNeeded = (s: string | undefined, encoded: boolean | undefined): string => {
    if (encoded && typeof s === 'string') return decodeURIComponent(s);
    return s ?? '';
  };

  const mergedCards: Array<CardRaw> = [];
  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];
    if (card.title === '' && mergedCards.length > 0) {
      const prev = mergedCards[mergedCards.length - 1];
      if (prev.sectionId === card.sectionId) {
        const prevBody = decodeIfNeeded(prev.body, prev.encoded);
        const cardBody = decodeIfNeeded(card.body, card.encoded);
        const prevTitle = decodeIfNeeded(prev.title, prev.encoded);
        const mergedBody = (prevBody || '') + '\n\n' + (cardBody || '');
        const needsEncoding = mergedBody.includes('"') || mergedBody.includes("'") || prevTitle.includes('"') || prevTitle.includes("'");
        if (needsEncoding) {
          prev.title = encodeURIComponent(prevTitle);
          prev.body = encodeURIComponent(mergedBody);
          prev.encoded = true;
        } else {
          prev.title = prevTitle;
          prev.body = mergedBody;
          prev.encoded = undefined;
        }
        if (card.lang && !prev.lang) prev.lang = card.lang;
        continue;
      }
    }
    mergedCards.push(card);
  }

  const finalCards: Array<ReferenceCardData> = mergedCards.map((c: CardRaw): ReferenceCardData => {
    const cardData: ReferenceCardData = {
      id: c.id,
      sectionId: c.sectionId,
      title: c.title,
      kind: 'text',
      encoded: c.encoded,
      body: c.body,
      lang: c.lang,
    };
    return cardData;
  });

  const docSource: ReferenceDocSource = {
    repo: url,
    path: url,
    ref: 'online',
    url: url,
    lang: 'zh',
    mode: 'online',
  };
  const doc: ReferenceDoc = {
    id: id,
    name: name,
    title: title,
    sections: sections,
    cards: finalCards,
    source: docSource,
  };
  return doc;
}

// Count total data rows in all markdown tables (GFM-style) within the given markdown.
// This is used for catalog "card count" display, treating each table row as one learning card.
// Keep behavior aligned with tools/sync_reference_docs.mjs.
export function countMarkdownTableRows(markdown: string, keepTags: boolean = false): number {
  const fmResult = extractFrontmatter(markdown);
  const body = fmResult.body;
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const normalizeLine = (raw: string): string => {
    const withoutComments = stripHtmlCommentsInLine(raw);
    if (keepTags) return withoutComments;
    return stripTagsInLine(withoutComments);
  };

  let totalRows = 0;
  let rehypeIgnoreDepth = 0;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const line = normalizeLine(rawLine);

    if (isRehypeIgnoreStart(rawLine)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(rawLine)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (isHorizontalRuleLine(line)) continue;

    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), fence.marker)) i++;
      continue;
    }

    // table header + separator
    if (line.includes('|') && i + 1 < lines.length) {
      const sep = normalizeLine(lines[i + 1]);
      if (!isTableSeparatorLine(sep)) continue;

      i += 2;
      while (i < lines.length) {
        const rowRaw = lines[i];
        // Don't cross ignore markers; outer loop needs to process ignore regions.
        if (isRehypeIgnoreStart(rowRaw) || isRehypeIgnoreEnd(rowRaw)) break;
        const rowLine = normalizeLine(rowRaw);
        if (!rowLine.trim() || !rowLine.includes('|')) break;
        if (isTableSeparatorLine(rowLine)) break;
        totalRows++;
        i++;
      }
      i--;
      continue;
    }
  }

  return totalRows;
}


