import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeTokens } from '../common/appTheme';
import { openExternalLink } from '../common/openExternalLink';

type MarkdownInlineKind = 'text' | 'bold' | 'italic' | 'code' | 'link';

interface MarkdownInlineToken {
  kind: MarkdownInlineKind;
  text: string;
  url?: string;
}

type MarkdownBlockKind = 'paragraph' | 'heading' | 'codeblock' | 'list';

interface MarkdownParagraphBlock {
  kind: 'paragraph';
  tokens: Array<MarkdownInlineToken>;
}

interface MarkdownHeadingBlock {
  kind: 'heading';
  level: number;
  tokens: Array<MarkdownInlineToken>;
}

interface MarkdownCodeBlock {
  kind: 'codeblock';
  language: string;
  code: string;
}

type MarkdownListRehypeStyle = 'default' | 'none' | 'arrow' | 'timeline';

interface MarkdownListBlock {
  kind: 'list';
  ordered: boolean;
  items: Array<Array<MarkdownInlineToken>>;
  rehypeClassNames?: Array<string>;
  rehypeStyle?: MarkdownListRehypeStyle;
  rehypeColumns?: Array<Array<Array<MarkdownInlineToken>>>;
}

type MarkdownTableRehypeStyle = 'default' | 'style-list' | 'style-list-arrow';

interface MarkdownTableBlock {
  kind: 'table';
  aligns: Array<MarkdownCellAlign>;
  header: Array<Array<MarkdownInlineToken>>;
  rows: Array<Array<Array<MarkdownInlineToken>>>;
  columnWidths: Array<number>;
  rehypeClassNames?: Array<string>;
  rehypeStyle?: MarkdownTableRehypeStyle;
  rehypeShowHeader?: boolean;
  rehypeLeftAlign?: boolean;
  rehypeWrapText?: boolean;
}

type MarkdownBlock = MarkdownParagraphBlock | MarkdownHeadingBlock | MarkdownCodeBlock | MarkdownListBlock | MarkdownTableBlock;

type MarkdownCellAlign = 'start' | 'center' | 'end';

interface ListMarkerMatch {
  ordered: boolean;
  markerLength: number;
}

function normalizeNewlines(input: string): string {
  return input.split('\r\n').join('\n').split('\r').join('\n');
}

function isRehypeIgnoreStartLine(trimmedLine: string): boolean {
  return /^<!--\s*rehype:ignore:start\s*-->$/.test(trimmedLine);
}

function isRehypeIgnoreEndLine(trimmedLine: string): boolean {
  return /^<!--\s*rehype:ignore:end\s*-->$/.test(trimmedLine);
}

interface RehypeDirective {
  classNames: Array<string>;
}

function mergeUniqueStrings(a: Array<string> | undefined, b: Array<string>): Array<string> {
  const out: Array<string> = (a ?? []).slice(0);
  for (let i = 0; i < b.length; i++) {
    const v = b[i];
    if (!v) continue;
    if (out.indexOf(v) >= 0) continue;
    out.push(v);
  }
  return out;
}

function parseRehypeDirective(trimmedLine: string): RehypeDirective | undefined {
  const m = /^<!--\s*rehype:([\s\S]*?)-->$/.exec(trimmedLine);
  if (!m) return undefined;
  const payload = String(m[1] ?? '').trim();
  if (!payload) return { classNames: [] };

  const parts = payload.split('&').map((s: string): string => s.trim()).filter(Boolean);
  const classNames: Array<string> = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const eq = part.indexOf('=');
    const key = (eq >= 0 ? part.slice(0, eq) : part).trim();
    const value = (eq >= 0 ? part.slice(eq + 1) : '').trim();
    if (key === 'className' || key === 'class') {
      const pieces = value.split(/\s+/).map((s: string): string => s.trim()).filter(Boolean);
      for (let j = 0; j < pieces.length; j++) {
        classNames.push(pieces[j]);
      }
    }
  }
  return { classNames };
}

type RehypeTargetKind = 'list' | 'table' | 'any';

function rehypeTargetKindFromClassNames(classNames: Array<string>): RehypeTargetKind {
  for (let i = 0; i < classNames.length; i++) {
    const c = classNames[i];
    if (!c) continue;
    if (c === 'style-none' || c === 'style-arrow' || c === 'style-timeline' || c.startsWith('cols-')) return 'list';
    if (c === 'style-list' || c === 'style-list-arrow' || c === 'show-header' || c === 'left-align' || c === 'wrap-text' || c === 'auto-wrap'
      || c === 'shortcuts' || c === 'shortcuts-last') return 'table';
  }
  return 'any';
}

function finalizeListBlockRehype(block: MarkdownListBlock): void {
  const classNames = block.rehypeClassNames ?? [];
  if (hasClassName(classNames, 'style-none')) {
    block.rehypeStyle = 'none';
  } else if (hasClassName(classNames, 'style-arrow')) {
    block.rehypeStyle = 'arrow';
  } else if (hasClassName(classNames, 'style-timeline')) {
    block.rehypeStyle = 'timeline';
  } else {
    block.rehypeStyle = 'default';
  }

  const cols = Math.max(1, parseColsFromClassNames(classNames));
  const items = block.items ?? [];
  const columns: Array<Array<Array<MarkdownInlineToken>>> = [];
  for (let c = 0; c < cols; c++) columns.push([]);
  const perCol = Math.max(1, Math.ceil(items.length / cols));
  for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
    const colIndex = Math.min(cols - 1, Math.floor(itemIndex / perCol));
    columns[colIndex].push(items[itemIndex]);
  }
  block.rehypeColumns = columns;
}

function finalizeTableBlockRehype(block: MarkdownTableBlock, fontSize: number, maxTableColumnWidth: number): void {
  const classNames = block.rehypeClassNames ?? [];
  block.rehypeShowHeader = hasClassName(classNames, 'show-header');
  block.rehypeLeftAlign = hasClassName(classNames, 'left-align');
  block.rehypeWrapText = hasClassName(classNames, 'wrap-text') || hasClassName(classNames, 'auto-wrap');

  if (hasClassName(classNames, 'style-list-arrow')) {
    block.rehypeStyle = 'style-list-arrow';
  } else if (hasClassName(classNames, 'style-list')) {
    block.rehypeStyle = 'style-list';
  } else {
    block.rehypeStyle = 'default';
  }

  // 默认不换行且不截断：列宽按内容自适应，超出屏幕由横向滚动承载。
  // 当显式启用 wrap-text/auto-wrap 时，限制单列最大宽度以促使换行。
  const maxColumnWidth = (block.rehypeWrapText ?? false) ? Math.max(fontSize * 12, maxTableColumnWidth * 0.6) : 0;
  block.columnWidths = computeColumnWidths(block.header, block.rows, fontSize, maxColumnWidth);
}

function applyRehypeClassNamesToBlock(
  block: MarkdownBlock,
  classNames: Array<string>,
  fontSize: number,
  maxTableColumnWidth: number
): void {
  if (!classNames.length) return;
  if (block.kind === 'list') {
    block.rehypeClassNames = mergeUniqueStrings(block.rehypeClassNames, classNames);
    finalizeListBlockRehype(block);
    return;
  }
  if (block.kind === 'table') {
    block.rehypeClassNames = mergeUniqueStrings(block.rehypeClassNames, classNames);
    finalizeTableBlockRehype(block, fontSize, maxTableColumnWidth);
    return;
  }
}

function parseListMarker(trimmedLine: string): ListMarkerMatch | null {
  if (trimmedLine.startsWith('- ') || trimmedLine.startsWith('* ') || trimmedLine.startsWith('+ ')) {
    return { ordered: false, markerLength: 2 };
  }
  if (trimmedLine.startsWith('• ')) {
    return { ordered: false, markerLength: 2 };
  }

  const dot = trimmedLine.indexOf('.');
  if (dot > 0 && dot + 1 < trimmedLine.length && trimmedLine.charAt(dot + 1) === ' ') {
    let allDigits = true;
    for (let i = 0; i < dot; i++) {
      const ch = trimmedLine.charAt(i);
      if (ch < '0' || ch > '9') {
        allDigits = false;
        break;
      }
    }
    if (allDigits) {
      return { ordered: true, markerLength: dot + 2 };
    }
  }
  return null;
}

function splitTableRow(trimmedLine: string): Array<string> {
  let line = trimmedLine.trim();
  if (line.startsWith('|')) {
    line = line.substring(1);
  }
  if (line.endsWith('|')) {
    line = line.substring(0, line.length - 1);
  }
  const parts = line.split('|');
  const cells: Array<string> = [];
  for (let i = 0; i < parts.length; i++) {
    cells.push(parts[i].trim());
  }
  return cells;
}

function looksLikeTableSeparatorLine(trimmedLine: string): boolean {
  if (trimmedLine.indexOf('|') < 0) return false;
  const cells = splitTableRow(trimmedLine);
  if (cells.length < 2) return false;
  for (let i = 0; i < cells.length; i++) {
    const raw = cells[i];
    const s = raw.split(' ').join('');
    if (!s) return false;
    let hasDash = false;
    for (let j = 0; j < s.length; j++) {
      const ch = s.charAt(j);
      if (ch === '-') hasDash = true;
      if (ch !== '-' && ch !== ':') return false;
    }
    if (!hasDash) return false;
  }
  return true;
}

function parseTableAligns(separatorLine: string): Array<MarkdownCellAlign> {
  const cells = splitTableRow(separatorLine);
  const aligns: Array<MarkdownCellAlign> = [];
  for (let i = 0; i < cells.length; i++) {
    const raw = cells[i];
    const s = raw.split(' ').join('');
    const starts = s.startsWith(':');
    const ends = s.endsWith(':');
    if (starts && ends) {
      aligns.push('center');
    } else if (ends) {
      aligns.push('end');
    } else {
      aligns.push('start');
    }
  }
  return aligns;
}

function padCells<T>(cells: Array<T>, targetLength: number, create: () => T): Array<T> {
  if (cells.length >= targetLength) return cells;
  const out = cells.slice(0);
  while (out.length < targetLength) {
    out.push(create());
  }
  return out;
}

function getTokensTextLength(tokens: Array<MarkdownInlineToken>): number {
  let len = 0;
  for (let i = 0; i < tokens.length; i++) {
    len += tokens[i].text.length;
  }
  return len;
}

function estimateTextWidth(text: string, fontSize: number): number {
  let width = 0;
  const chars = Array.from(text ?? '');
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    if (ch === ' ') {
      width += fontSize * 0.35;
      continue;
    }

    const code = ch.codePointAt(0) ?? 0;
    const isWide = (
      (code >= 0x1100 && code <= 0x115F) ||
      (code >= 0x2E80 && code <= 0xA4CF) ||
      (code >= 0xAC00 && code <= 0xD7A3) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0xFE10 && code <= 0xFE6F) ||
      (code >= 0xFF01 && code <= 0xFF60) ||
      (code >= 0xFFE0 && code <= 0xFFE6)
    );
    if (isWide) {
      width += fontSize * 1;
      continue;
    }

    const isDigit = ch >= '0' && ch <= '9';
    if (isDigit) {
      width += fontSize * 0.6;
      continue;
    }

    const isUpper = ch >= 'A' && ch <= 'Z';
    if (isUpper) {
      width += fontSize * 0.75;
      continue;
    }

    const isLower = ch >= 'a' && ch <= 'z';
    if (isLower) {
      width += fontSize * 0.6;
      continue;
    }

    width += fontSize * 0.45;
  }
  return width;
}

function estimateTokensWidth(tokens: Array<MarkdownInlineToken>, fontSize: number): number {
  let width = 0;
  for (let i = 0; i < tokens.length; i++) {
    width += estimateTextWidth(tokens[i].text, fontSize);
  }
  return width;
}

interface MarkdownInlineStyledParams {
  tokens: Array<MarkdownInlineToken>;
  fontSize: number;
  color: number;
  weight: FontWeight;
  align: TextAlign;
  linkColor: number;
  codeTextColor: number;
  hostContext: object | undefined;
  maxLines?: number;
  overflow?: TextOverflow;
}

interface MarkdownViewParams {
  markdown: string;
  inlineOnly?: boolean;
  fontSize?: number;
  fontColor?: number;
  fontWeight?: FontWeight;
  theme?: AppThemeTokens;
  unboundedTableColumns?: boolean;
  learningMode?: boolean;
  hostContext?: object;
}

function computeColumnWidths(
  header: Array<Array<MarkdownInlineToken>>,
  rows: Array<Array<Array<MarkdownInlineToken>>>,
  fontSize: number,
  maxColumnWidth: number,
): Array<number> {
  const colCount = header.length > 0 ? header.length : (rows.length > 0 ? rows[0].length : 0);
  const maxContentWidths: Array<number> = [];
  for (let c = 0; c < colCount; c++) {
    maxContentWidths.push(0);
  }

  for (let c = 0; c < header.length; c++) {
    const w = estimateTokensWidth(header[c], fontSize);
    if (w > maxContentWidths[c]) {
      maxContentWidths[c] = w;
    }
  }

  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    for (let c = 0; c < row.length && c < colCount; c++) {
      const w = estimateTokensWidth(row[c], fontSize);
      if (w > maxContentWidths[c]) {
        maxContentWidths[c] = w;
      }
    }
  }

  const widths: Array<number> = [];
  // 经验值：列宽估算需要留出少量冗余，避免因字体度量/取整导致最后 1 个字被 Clip 掉
  const cellPaddingLR = fontSize * 1.4;
  const maxW = maxColumnWidth > 0 ? maxColumnWidth : 0;
  for (let c = 0; c < colCount; c++) {
    const estimated = maxContentWidths[c] + cellPaddingLR;
    // 第一列通常是“键/名称”，在清单表格中要求不换行，因此列宽按内容自适应（允许横向滚动）
    if (c === 0) {
      widths.push(estimated);
      continue;
    }
    widths.push(maxW > 0 && estimated > maxW ? maxW : estimated);
  }

  return widths;
}

function appendTextToken(tokens: Array<MarkdownInlineToken>, text: string): void {
  if (!text) return;
  const lastIndex = tokens.length - 1;
  if (lastIndex >= 0 && tokens[lastIndex].kind === 'text') {
    tokens[lastIndex].text = tokens[lastIndex].text + text;
    return;
  }
  tokens.push({ kind: 'text', text });
}

function parseInlineTokens(text: string): Array<MarkdownInlineToken> {
  const tokens: Array<MarkdownInlineToken> = [];
  const len = text.length;
  let i = 0;

  const urlRegex = /(https?:\/\/[^\s)]+|www\.[^\s)]+|[a-z0-9][a-z0-9.-]*\.[a-z]{2,}[^\s)]*)/ig;

  while (i < len) {
    const ch = text.charAt(i);

    // HTML 换行：支持 <br> / <br/> / <br />，渲染时应产生硬换行
    if (ch === '<') {
      const rest = text.substring(i);
      const m = /^<br\s*\/?>/i.exec(rest);
      if (m) {
        appendTextToken(tokens, '\n');
        i += m[0].length;
        continue;
      }
    }

    if (ch === '\\' && i + 1 < len) {
      appendTextToken(tokens, text.charAt(i + 1));
      i += 2;
      continue;
    }

    if (ch === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        tokens.push({ kind: 'code', text: text.substring(i + 1, end) });
        i = end + 1;
        continue;
      }
    }

    if (ch === '*' || ch === '_') {
      const nextIsSame = i + 1 < len && text.charAt(i + 1) === ch;
      const markerLen = nextIsSame ? 2 : 1;
      const marker = nextIsSame ? `${ch}${ch}` : ch;
      const end = text.indexOf(marker, i + markerLen);
      if (end > i + markerLen) {
        const inner = text.substring(i + markerLen, end);
        tokens.push({ kind: nextIsSame ? 'bold' : 'italic', text: inner });
        i = end + markerLen;
        continue;
      }
    }

    if (ch === '[') {
      const closeBracket = text.indexOf(']', i + 1);
      const openParen = closeBracket >= 0 ? text.indexOf('(', closeBracket + 1) : -1;
      const closeParen = openParen >= 0 ? text.indexOf(')', openParen + 1) : -1;
      if (closeBracket > i + 1 && openParen === closeBracket + 1 && closeParen > openParen + 1) {
        const label = text.substring(i + 1, closeBracket);
        const url = text.substring(openParen + 1, closeParen);
        tokens.push({ kind: 'link', text: label, url });
        i = closeParen + 1;
        continue;
      }
    }

    let nextSpecial = len;
    const nextBackslash = text.indexOf('\\', i);
    const nextTick = text.indexOf('`', i);
    const nextStar = text.indexOf('*', i);
    const nextUnderscore = text.indexOf('_', i);
    const nextBracket = text.indexOf('[', i);
    const nextAngle = text.indexOf('<', i);

    if (nextBackslash >= 0 && nextBackslash < nextSpecial) nextSpecial = nextBackslash;
    if (nextTick >= 0 && nextTick < nextSpecial) nextSpecial = nextTick;
    if (nextStar >= 0 && nextStar < nextSpecial) nextSpecial = nextStar;
    if (nextUnderscore >= 0 && nextUnderscore < nextSpecial) nextSpecial = nextUnderscore;
    if (nextBracket >= 0 && nextBracket < nextSpecial) nextSpecial = nextBracket;
    if (nextAngle >= 0 && nextAngle < nextSpecial) nextSpecial = nextAngle;

    if (nextSpecial <= i) {
      appendTextToken(tokens, ch);
      i += 1;
      continue;
    }

    urlRegex.lastIndex = i;
    const urlMatch = urlRegex.exec(text);
    if (urlMatch && urlMatch.index >= i && urlMatch.index < nextSpecial) {
      const urlStart = urlMatch.index;
      if (urlStart > i) {
        appendTextToken(tokens, text.substring(i, urlStart));
      }

      const raw = urlMatch[0];
      let cleaned = raw;
      while (cleaned.length > 0) {
        const lastCh = cleaned.charAt(cleaned.length - 1);
        const isTrailing = lastCh === '.' || lastCh === ',' || lastCh === ';' || lastCh === ':' || lastCh === '!' || lastCh === '?' || lastCh === ')' || lastCh === ']' || lastCh === '}';
        if (!isTrailing) break;
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }

      if (cleaned) {
        tokens.push({ kind: 'link', text: cleaned, url: cleaned });
      }
      if (cleaned.length < raw.length) {
        appendTextToken(tokens, raw.substring(cleaned.length));
      }

      i = urlStart + raw.length;
      continue;
    }

    appendTextToken(tokens, text.substring(i, nextSpecial));
    i = nextSpecial;
  }

  return tokens;
}

function stripHtmlComments(lines: Array<string>): Array<string> {
  const out: Array<string> = [];
  let inComment = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    if (!inComment && trimmed.startsWith('<!--')) {
      inComment = trimmed.indexOf('-->') < 0;
      continue;
    }
    if (inComment) {
      if (trimmed.indexOf('-->') >= 0) {
        inComment = false;
      }
      continue;
    }
    out.push(line);
  }
  return out;
}

function parseBlocks(markdown: string, fontSize: number, maxTableColumnWidth: number): Array<MarkdownBlock> {
  const text = normalizeNewlines(markdown);
  const rawLines = text.split('\n');
  const blocks: Array<MarkdownBlock> = [];

  let pendingRehypeClassNames: Array<string> = [];
  let rehypeIgnoreDepth = 0;
  let inHtmlComment = false;

  let i = 0;
  while (i < rawLines.length) {
    const line = rawLines[i];
    const trimmed = line.trim();

    if (inHtmlComment) {
      if (trimmed.indexOf('-->') >= 0) {
        inHtmlComment = false;
      }
      i += 1;
      continue;
    }

    if (trimmed) {
      if (isRehypeIgnoreStartLine(trimmed)) {
        rehypeIgnoreDepth += 1;
        i += 1;
        continue;
      }
      if (isRehypeIgnoreEndLine(trimmed)) {
        if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth -= 1;
        i += 1;
        continue;
      }
      if (rehypeIgnoreDepth > 0) {
        i += 1;
        continue;
      }

      if (trimmed.startsWith('<!--')) {
        const directive = parseRehypeDirective(trimmed);
        if (directive) {
          const classNames = directive.classNames ?? [];
          const targetKind = rehypeTargetKindFromClassNames(classNames);
          const lastIndex = blocks.length - 1;
          if (targetKind !== 'any' && lastIndex >= 0 && blocks[lastIndex].kind === targetKind) {
            applyRehypeClassNamesToBlock(blocks[lastIndex], classNames, fontSize, maxTableColumnWidth);
          } else {
            pendingRehypeClassNames = mergeUniqueStrings(pendingRehypeClassNames, classNames);
          }
          i += 1;
          continue;
        }

        // 非 rehype 的 HTML 注释：跳过（兼容多行注释块）
        inHtmlComment = trimmed.indexOf('-->') < 0;
        i += 1;
        continue;
      }
    }

    if (!trimmed) {
      i += 1;
      continue;
    }

    if (trimmed.startsWith('```')) {
      const language = trimmed.substring(3).trim();
      const codeLines: Array<string> = [];
      i += 1;
      while (i < rawLines.length) {
        const l = rawLines[i];
        if (l.trim().startsWith('```')) {
          i += 1;
          break;
        }
        codeLines.push(l);
        i += 1;
      }
      const block: MarkdownCodeBlock = { kind: 'codeblock', language, code: codeLines.join('\n') };
      // 目前仅对 list/table 处理 rehype className；其它 block 上的指令直接消费掉，避免泄露到后续 block。
      pendingRehypeClassNames = [];
      blocks.push(block);
      continue;
    }

    if (trimmed.startsWith('#')) {
      let level = 0;
      while (level < trimmed.length && trimmed.charAt(level) === '#') {
        level += 1;
      }
      const after = trimmed.substring(level);
      if (after.startsWith(' ')) {
        const title = after.trim();
        const block: MarkdownHeadingBlock = { kind: 'heading', level, tokens: parseInlineTokens(title) };
        pendingRehypeClassNames = [];
        blocks.push(block);
        i += 1;
        continue;
      }
    }

    if (trimmed.indexOf('|') >= 0 && i + 1 < rawLines.length) {
      const nextTrimmed = rawLines[i + 1].trim();
      if (looksLikeTableSeparatorLine(nextTrimmed)) {
        const headerIsSeparator = looksLikeTableSeparatorLine(trimmed);
        const aligns: Array<MarkdownCellAlign> = parseTableAligns(headerIsSeparator ? trimmed : nextTrimmed);

        let header: Array<Array<MarkdownInlineToken>> = [];
        if (!headerIsSeparator) {
          const headerCells = padCells(splitTableRow(trimmed), aligns.length, () => '');
          header = [];
          for (let c = 0; c < headerCells.length; c++) {
            header.push(parseInlineTokens(headerCells[c]));
          }
        }

        const rows: Array<Array<Array<MarkdownInlineToken>>> = [];
        i += 2;
        while (i < rawLines.length) {
          const rowLine = rawLines[i];
          const rowTrim = rowLine.trim();
          if (!rowTrim) break;
          if (rowTrim.indexOf('|') < 0) break;
          if (rowTrim.startsWith('```')) break;
          if (looksLikeTableSeparatorLine(rowTrim)) {
            i += 1;
            continue;
          }
          const rowCells = splitTableRow(rowTrim);
          const rowTokens: Array<Array<MarkdownInlineToken>> = [];
          const padded = padCells(rowCells, aligns.length, () => '');
          for (let c = 0; c < padded.length; c++) {
            rowTokens.push(parseInlineTokens(padded[c]));
          }
          rows.push(rowTokens);
          i += 1;
        }

        const columnWidths = computeColumnWidths(header, rows, fontSize, maxTableColumnWidth);
        const block: MarkdownTableBlock = { kind: 'table', aligns, header, rows, columnWidths };
        if (pendingRehypeClassNames.length) {
          applyRehypeClassNamesToBlock(block, pendingRehypeClassNames, fontSize, maxTableColumnWidth);
        }
        pendingRehypeClassNames = [];
        finalizeTableBlockRehype(block, fontSize, maxTableColumnWidth);
        blocks.push(block);
        continue;
      }
    }

    const marker = parseListMarker(trimmed);
    if (marker) {
      const items: Array<Array<MarkdownInlineToken>> = [];
      const ordered = marker.ordered;
      while (i < rawLines.length) {
        const current = rawLines[i];
        const currentTrim = current.trim();
        if (!currentTrim) break;
        const m = parseListMarker(currentTrim);
        if (!m || m.ordered !== ordered) break;
        const itemText = currentTrim.substring(m.markerLength);
        items.push(parseInlineTokens(itemText));
        i += 1;
      }
      const block: MarkdownListBlock = { kind: 'list', ordered, items };
      if (pendingRehypeClassNames.length) {
        applyRehypeClassNamesToBlock(block, pendingRehypeClassNames, fontSize, maxTableColumnWidth);
      }
      pendingRehypeClassNames = [];
      finalizeListBlockRehype(block);
      blocks.push(block);
      continue;
    }

    const paragraphLines: Array<string> = [];
    while (i < rawLines.length) {
      const l = rawLines[i];
      const t = l.trim();
      if (!t) break;
      if (t.startsWith('```')) break;
      if (t.startsWith('#') && t.indexOf(' ') >= 0) break;
      if (parseListMarker(t)) break;
      if (t.startsWith('<!--')) break;
      paragraphLines.push(l);
      i += 1;
    }
    const block: MarkdownParagraphBlock = { kind: 'paragraph', tokens: parseInlineTokens(paragraphLines.join('\n')) };
    pendingRehypeClassNames = [];
    blocks.push(block);
  }

  return blocks;
}

@Builder
function MarkdownInlineStyled($$: MarkdownInlineStyledParams): void {
  Text() {
    ForEach($$.tokens, (token: MarkdownInlineToken, index: number) => {
      if (token.kind === 'text') {
        Span(token.text);
      } else if (token.kind === 'bold') {
        Span(token.text).fontWeight(FontWeight.Bold);
      } else if (token.kind === 'italic') {
        Span(token.text).fontStyle(FontStyle.Italic);
      } else if (token.kind === 'code') {
        Span(token.text).fontFamily('monospace').fontColor($$.codeTextColor);
      } else {
        Span(token.text)
          .fontColor($$.linkColor)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => openExternalLink($$.hostContext, token.url ?? token.text));
      }
    }, (_: MarkdownInlineToken, index: number) => `${index}`);
  }
  .fontSize($$.fontSize)
  .fontColor($$.color)
  .fontWeight($$.weight)
  .textAlign($$.align)
  .width('100%')
  .maxLines($$.maxLines ?? 999)
  .textOverflow({ overflow: $$.overflow ?? TextOverflow.Clip });
}

function tableTextAlignForColumn(aligns: Array<MarkdownCellAlign>, colIndex: number): TextAlign {
  const key: MarkdownCellAlign = aligns.length > colIndex ? aligns[colIndex] : 'start';
  if (key === 'center') return TextAlign.Center;
  if (key === 'end') return TextAlign.End;
  return TextAlign.Start;
}

function hasClassName(classNames: Array<string> | undefined, value: string): boolean {
  if (!classNames || !value) return false;
  return classNames.indexOf(value) >= 0;
}

function parseColsFromClassNames(classNames: Array<string> | undefined): number {
  if (!classNames) return 1;
  for (let i = 0; i < classNames.length; i++) {
    const c = classNames[i];
    if (!c) continue;
    if (!c.startsWith('cols-')) continue;
    const n = Number(c.substring('cols-'.length));
    if (Number.isFinite(n) && n >= 1) return Math.max(1, Math.min(Math.floor(n), 6));
  }
  return 1;
}

function isCellTokensEmpty(tokens: Array<MarkdownInlineToken>): boolean {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].text.trim().length > 0) return false;
  }
  return true;
}

function tokensHasHardLineBreak(tokens: Array<MarkdownInlineToken>): boolean {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].text.indexOf('\n') >= 0) return true;
  }
  return false;
}

function findFirstNonEmptyColumnIndex(row: Array<Array<MarkdownInlineToken>>): number {
  for (let i = 0; i < row.length; i++) {
    if (!isCellTokensEmpty(row[i])) return i;
  }
  return -1;
}

function maskCellTokens(tokens: Array<MarkdownInlineToken>): Array<MarkdownInlineToken> {
  let totalLength: number = 0;
  for (let i = 0; i < tokens.length; i++) {
    totalLength += tokens[i].text.length;
  }
  const maskLength: number = Math.max(1, Math.min(totalLength, 8));
  const masked: Array<MarkdownInlineToken> = [{ kind: 'text', text: '*'.repeat(maskLength) }];
  return masked;
}

function getCellDisplayTokensForLearning(
  row: Array<Array<MarkdownInlineToken>>,
  colIndex: number,
  learningMode: boolean
): Array<MarkdownInlineToken> {
  const cell: Array<MarkdownInlineToken> = row[colIndex];
  if (!learningMode) return cell;
  if (isCellTokensEmpty(cell)) return cell;
  const firstNonEmptyCol: number = findFirstNonEmptyColumnIndex(row);
  if (colIndex === firstNonEmptyCol) return cell;
  return maskCellTokens(cell);
}

function headingFontSizeForLevel(baseFontSize: number, level: number): number {
  if (level <= 1) return baseFontSize + 6;
  if (level === 2) return baseFontSize + 4;
  if (level === 3) return baseFontSize + 2;
  return baseFontSize;
}

@Builder
export function MarkdownView($$: MarkdownViewParams): void {
  Column({ space: ($$.inlineOnly ?? false) ? 0 : 6 }) {
    if ($$.inlineOnly ?? false) {
      MarkdownInlineStyled({
        tokens: parseInlineTokens($$.markdown ?? ''),
        fontSize: $$.fontSize ?? 15,
        color: $$.fontColor ?? 0x222222,
        weight: $$.fontWeight ?? FontWeight.Normal,
        align: TextAlign.Start,
        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
        hostContext: $$.hostContext,
      });
    } else {
      ForEach(parseBlocks($$.markdown ?? '', $$.fontSize ?? 15, ($$.unboundedTableColumns ?? false) ? 0 : ($$.fontSize ?? 15) * 30), (block: MarkdownBlock, index: number) => {
        if (block.kind === 'codeblock') {
          Scroll() {
            Text(block.code)
              .fontFamily('monospace')
              .fontSize(($$.fontSize ?? 15) - 2)
              .fontColor(($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor)
              .textAlign(TextAlign.Start)
              .constraintSize({ minWidth: '100%' })
              .maxLines(999);
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .backgroundColor(($$.theme ?? getAppThemeTokens('light')).markdown.codeBackgroundColor)
          .borderRadius(($$.fontSize ?? 15) * 0.5)
          .padding(($$.fontSize ?? 15) * 0.6)
          .width('100%');
        } else if (block.kind === 'heading') {
          MarkdownInlineStyled({
            tokens: block.tokens,
            fontSize: headingFontSizeForLevel($$.fontSize ?? 15, block.level),
            color: ($$.theme ?? getAppThemeTokens('light')).markdown.headingColor,
            weight: FontWeight.Bold,
            align: TextAlign.Start,
            linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
            codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
            hostContext: $$.hostContext,
          });
        } else if (block.kind === 'list') {
          if ((block.rehypeStyle ?? 'default') === 'none') {
            if ((block.rehypeColumns?.length ?? 0) > 1) {
              Row({ space: ($$.fontSize ?? 15) * 1 }) {
                ForEach(block.rehypeColumns ?? [], (colItems: Array<Array<MarkdownInlineToken>>, colIndex: number) => {
                  Column({ space: ($$.fontSize ?? 15) * 0.25 }) {
                    ForEach(colItems, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
                      MarkdownInlineStyled({
                        tokens: item,
                        fontSize: $$.fontSize ?? 15,
                        color: $$.fontColor ?? 0x222222,
                        weight: $$.fontWeight ?? FontWeight.Normal,
                        align: TextAlign.Start,
                        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                        hostContext: $$.hostContext,
                      });
                    }, (_: Array<MarkdownInlineToken>, itemIndex: number) => `${index}:none:c${colIndex}:${itemIndex}`);
                  }
                  .layoutWeight(1);
                }, (_: Array<Array<MarkdownInlineToken>>, colIndex: number) => `${index}:none:col:${colIndex}`);
              }
              .alignItems(VerticalAlign.Top);
            } else {
              Column({ space: ($$.fontSize ?? 15) * 0.25 }) {
                ForEach(block.items, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
                  MarkdownInlineStyled({
                    tokens: item,
                    fontSize: $$.fontSize ?? 15,
                    color: $$.fontColor ?? 0x222222,
                    weight: $$.fontWeight ?? FontWeight.Normal,
                    align: TextAlign.Start,
                    linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                    codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                    hostContext: $$.hostContext,
                  });
                }, (_: Array<MarkdownInlineToken>, itemIndex: number) => `${index}:none:${itemIndex}`);
              }
            }
          } else {
            if ((block.rehypeColumns?.length ?? 0) > 1) {
              Row({ space: ($$.fontSize ?? 15) * 1 }) {
                ForEach(block.rehypeColumns ?? [], (colItems: Array<Array<MarkdownInlineToken>>, colIndex: number) => {
                  Column({ space: ($$.fontSize ?? 15) * 0.25 }) {
                    ForEach(colItems, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
                      Row({ space: ($$.fontSize ?? 15) * 0.5 }) {
                        Text((block.rehypeStyle ?? 'default') === 'arrow' ? '▶' : (((block.rehypeStyle ?? 'default') === 'timeline') ? '●' : '\u2022'))
                          .fontSize(($$.fontSize ?? 15) * 0.9)
                          .fontColor(((block.rehypeStyle ?? 'default') === 'arrow' || (block.rehypeStyle ?? 'default') === 'timeline')
                            ? ($$.theme ?? getAppThemeTokens('light')).accentColor
                            : ($$.fontColor ?? 0x222222))
                          .width(($$.fontSize ?? 15) * 1.4);
                        Column() {
                          MarkdownInlineStyled({
                            tokens: item,
                            fontSize: $$.fontSize ?? 15,
                            color: $$.fontColor ?? 0x222222,
                            weight: $$.fontWeight ?? FontWeight.Normal,
                            align: TextAlign.Start,
                            linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                            codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                            hostContext: $$.hostContext,
                          });
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start);
                      }
                    }, (_: Array<MarkdownInlineToken>, itemIndex: number) => `${index}:styled:c${colIndex}:${itemIndex}`);
                  }
                  .layoutWeight(1);
                }, (_: Array<Array<MarkdownInlineToken>>, colIndex: number) => `${index}:styled:col:${colIndex}`);
              }
              .alignItems(VerticalAlign.Top);
            } else {
              Column({ space: ($$.fontSize ?? 15) * 0.25 }) {
                ForEach(block.items, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
                  Row({ space: ($$.fontSize ?? 15) * 0.5 }) {
                    Text(block.ordered && (block.rehypeStyle ?? 'default') === 'default' ? `${itemIndex + 1}.` : ((block.rehypeStyle ?? 'default') === 'arrow' ? '▶' : (((block.rehypeStyle ?? 'default') === 'timeline') ? '●' : '\u2022')))
                      .fontSize(block.ordered && (block.rehypeStyle ?? 'default') === 'default' ? ($$.fontSize ?? 15) : (($$.fontSize ?? 15) * 0.9))
                      .fontColor(((block.rehypeStyle ?? 'default') === 'arrow' || (block.rehypeStyle ?? 'default') === 'timeline')
                        ? ($$.theme ?? getAppThemeTokens('light')).accentColor
                        : ($$.fontColor ?? 0x222222))
                      .width(($$.fontSize ?? 15) * 1.4);
                    Column() {
                      MarkdownInlineStyled({
                        tokens: item,
                        fontSize: $$.fontSize ?? 15,
                        color: $$.fontColor ?? 0x222222,
                        weight: $$.fontWeight ?? FontWeight.Normal,
                        align: TextAlign.Start,
                        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                        hostContext: $$.hostContext,
                      });
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start);
                  }
                }, (_: Array<MarkdownInlineToken>, itemIndex: number) => `${index}:styled:${itemIndex}:${block.ordered}`);
              }
            }
          }
        } else if (block.kind === 'table') {
          if (((block.rehypeStyle ?? 'default') === 'style-list' || (block.rehypeStyle ?? 'default') === 'style-list-arrow')
            && block.rows.length > 0
            && (block.rows[0]?.length ?? 0) === 2) {
            Column({ space: ($$.fontSize ?? 15) * 0.6 }) {
              ForEach(block.rows, (row: Array<Array<MarkdownInlineToken>>, rowIndex: number) => {
                Column({ space: ($$.fontSize ?? 15) * 0.35 }) {
                  Row({ space: ($$.fontSize ?? 15) * 0.45 }) {
                    if ((block.rehypeStyle ?? 'default') === 'style-list-arrow') {
                      Text('▶')
                        .fontSize(($$.fontSize ?? 15) * 0.9)
                        .fontColor(($$.theme ?? getAppThemeTokens('light')).accentColor);
                    }

                    Column() {
                      MarkdownInlineStyled({
                        tokens: row[0],
                        fontSize: $$.fontSize ?? 15,
                        color: ($$.theme ?? getAppThemeTokens('light')).markdown.headingColor,
                        weight: FontWeight.Bold,
                        align: TextAlign.Start,
                        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                        hostContext: $$.hostContext,
                        maxLines: ((block.rehypeWrapText ?? false) || tokensHasHardLineBreak(row[0])) ? 999 : 1,
                      });
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start);
                  }

                  MarkdownInlineStyled({
                    tokens: row[1],
                    fontSize: $$.fontSize ?? 15,
                    color: $$.fontColor ?? 0x222222,
                    weight: FontWeight.Normal,
                    align: TextAlign.Start,
                    linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                    codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                    hostContext: $$.hostContext,
                  });
                }
                .padding(($$.fontSize ?? 15) * 0.7)
                .backgroundColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableCellBackgroundColor)
                .borderRadius(($$.fontSize ?? 15) * 0.6)
                .borderWidth(1)
                .borderColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableBorderColor);
              }, (_: Array<Array<MarkdownInlineToken>>, rowIndex: number) => `${index}:listTable:${rowIndex}`);
            }
            .width('100%');
          } else {
            Scroll() {
              Column({ space: 0 }) {
                if ((block.rehypeShowHeader ?? false) && block.header.length > 0) {
                  Row({ space: 0 }) {
                    ForEach(block.header, (cell: Array<MarkdownInlineToken>, colIndex: number) => {
                      Column() {
                        MarkdownInlineStyled({
                          tokens: cell,
                          fontSize: $$.fontSize ?? 15,
                          color: ($$.theme ?? getAppThemeTokens('light')).markdown.headingColor,
                          weight: FontWeight.Bold,
                          align: ((block.rehypeLeftAlign ?? false) && colIndex === block.header.length - 1) ? TextAlign.Start : tableTextAlignForColumn(block.aligns, colIndex),
                          linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                          codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                          hostContext: $$.hostContext,
                          maxLines: ((block.rehypeWrapText ?? false) || tokensHasHardLineBreak(cell)) ? 999 : 1,
                          overflow: TextOverflow.Clip,
                        });
                      }
                      .width(block.columnWidths.length > colIndex ? block.columnWidths[colIndex] : ($$.fontSize ?? 15) * 4)
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: ($$.fontSize ?? 15) * 0.5, right: ($$.fontSize ?? 15) * 0.5, top: ($$.fontSize ?? 15) * 0.4, bottom: ($$.fontSize ?? 15) * 0.4 })
                      .backgroundColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableHeaderBackgroundColor)
                      .borderWidth(1)
                      .borderColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableBorderColor);
                    }, (_: Array<MarkdownInlineToken>, colIndex: number) => `${index}:h:${colIndex}`);
                  }
                }

                ForEach(block.rows, (row: Array<Array<MarkdownInlineToken>>, rowIndex: number) => {
                  Row({ space: 0 }) {
                    ForEach(row, (_cell: Array<MarkdownInlineToken>, colIndex: number) => {
                      Column() {
                        MarkdownInlineStyled({
                          tokens: getCellDisplayTokensForLearning(row, colIndex, $$.learningMode ?? false),
                          fontSize: $$.fontSize ?? 15,
                          color: $$.fontColor ?? 0x222222,
                          weight: FontWeight.Normal,
                          align: ((block.rehypeLeftAlign ?? false) && colIndex === row.length - 1) ? TextAlign.Start : tableTextAlignForColumn(block.aligns, colIndex),
                          linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                          codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                          hostContext: $$.hostContext,
                          // 默认表格单元格不换行；仅在显式指定 wrap-text/auto-wrap 时才允许换行
                          maxLines: ((block.rehypeWrapText ?? false)
                            || tokensHasHardLineBreak(getCellDisplayTokensForLearning(row, colIndex, $$.learningMode ?? false))) ? 999 : 1,
                          overflow: TextOverflow.Clip,
                        });
                      }
                      .width(block.columnWidths.length > colIndex ? block.columnWidths[colIndex] : ($$.fontSize ?? 15) * 4)
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: ($$.fontSize ?? 15) * 0.5, right: ($$.fontSize ?? 15) * 0.5, top: ($$.fontSize ?? 15) * 0.4, bottom: ($$.fontSize ?? 15) * 0.4 })
                      .backgroundColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableCellBackgroundColor)
                      .borderWidth(1)
                      .borderColor(($$.theme ?? getAppThemeTokens('light')).markdown.tableBorderColor);
                    }, (_: Array<MarkdownInlineToken>, colIndex: number) => `${index}:${rowIndex}:${colIndex}:${$$.learningMode ?? false}`);
                  }
                }, (_: Array<Array<MarkdownInlineToken>>, rowIndex: number) => `${index}:r:${rowIndex}`);
              }
              .alignItems(HorizontalAlign.Start)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off);
          }
        } else {
          MarkdownInlineStyled({
            tokens: block.tokens,
            fontSize: $$.fontSize ?? 15,
            color: $$.fontColor ?? 0x222222,
            weight: $$.fontWeight ?? FontWeight.Normal,
            align: TextAlign.Start,
            linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
            codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
            hostContext: $$.hostContext,
          });
        }
      }, (_: MarkdownBlock, index: number) => `${index}`);
    }
  }
}
