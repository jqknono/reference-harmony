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

interface MarkdownListBlock {
  kind: 'list';
  ordered: boolean;
  items: Array<Array<MarkdownInlineToken>>;
}

interface MarkdownTableBlock {
  kind: 'table';
  aligns: Array<MarkdownCellAlign>;
  header: Array<Array<MarkdownInlineToken>>;
  rows: Array<Array<Array<MarkdownInlineToken>>>;
  columnWidths: Array<number>;
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
  const cellPaddingLR = fontSize * 1;
  const maxW = maxColumnWidth > 0 ? maxColumnWidth : 0;
  for (let c = 0; c < colCount; c++) {
    const estimated = maxContentWidths[c] + cellPaddingLR;
    // 每个字符约 8px 宽度（中文约 14px），加上 padding 16px
    // 短内容：最小 50px
    // 中等内容：按字符数计算
    // 长内容：最大 400px，让内容换行
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

    if (nextBackslash >= 0 && nextBackslash < nextSpecial) nextSpecial = nextBackslash;
    if (nextTick >= 0 && nextTick < nextSpecial) nextSpecial = nextTick;
    if (nextStar >= 0 && nextStar < nextSpecial) nextSpecial = nextStar;
    if (nextUnderscore >= 0 && nextUnderscore < nextSpecial) nextSpecial = nextUnderscore;
    if (nextBracket >= 0 && nextBracket < nextSpecial) nextSpecial = nextBracket;

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
  const rawLines = stripHtmlComments(text.split('\n'));
  const blocks: Array<MarkdownBlock> = [];

  let i = 0;
  while (i < rawLines.length) {
    const line = rawLines[i];
    const trimmed = line.trim();

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
      blocks.push({ kind: 'codeblock', language, code: codeLines.join('\n') });
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
        blocks.push({ kind: 'heading', level, tokens: parseInlineTokens(title) });
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
        blocks.push({ kind: 'table', aligns, header, rows, columnWidths });
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
      blocks.push({ kind: 'list', ordered, items });
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
      paragraphLines.push(l);
      i += 1;
    }
    blocks.push({ kind: 'paragraph', tokens: parseInlineTokens(paragraphLines.join('\n')) });
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

function isCellTokensEmpty(tokens: Array<MarkdownInlineToken>): boolean {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].text.trim().length > 0) return false;
  }
  return true;
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
          Column({ space: ($$.fontSize ?? 15) * 0.2 }) {
            ForEach(block.items, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
              Row({ space: ($$.fontSize ?? 15) * 0.5 }) {
                Text(block.ordered ? `${itemIndex + 1}.` : '\u2022')
                  .fontSize($$.fontSize ?? 15)
                  .fontColor($$.fontColor ?? 0x222222);
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
            }, (_: Array<MarkdownInlineToken>, itemIndex: number) => `${index}:${itemIndex}`);
          }
        } else if (block.kind === 'table') {
          Scroll() {
            Column({ space: 0 }) {
              if (block.header.length > 0) {
                Row({ space: 0 }) {
                  ForEach(block.header, (cell: Array<MarkdownInlineToken>, colIndex: number) => {
                    Column() {
                      MarkdownInlineStyled({
                        tokens: cell,
                        fontSize: $$.fontSize ?? 15,
                        color: ($$.theme ?? getAppThemeTokens('light')).markdown.headingColor,
                        weight: FontWeight.Bold,
                        align: tableTextAlignForColumn(block.aligns, colIndex),
                        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                        hostContext: $$.hostContext,
                        maxLines: 1,
                        overflow: ($$.unboundedTableColumns ?? false) ? TextOverflow.Clip : TextOverflow.Ellipsis,
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
                        align: tableTextAlignForColumn(block.aligns, colIndex),
                        linkColor: ($$.theme ?? getAppThemeTokens('light')).markdown.linkColor,
                        codeTextColor: ($$.theme ?? getAppThemeTokens('light')).markdown.codeTextColor,
                        hostContext: $$.hostContext,
                        maxLines: ($$.unboundedTableColumns ?? false) ? 1 : 999,
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
