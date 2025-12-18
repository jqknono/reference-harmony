import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeTokens } from '../common/appTheme';

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

function computeColumnWidths(header: Array<Array<MarkdownInlineToken>>, rows: Array<Array<Array<MarkdownInlineToken>>>): Array<number> {
  const colCount = header.length > 0 ? header.length : (rows.length > 0 ? rows[0].length : 0);
  const maxLengths: Array<number> = [];
  for (let c = 0; c < colCount; c++) {
    maxLengths.push(0);
  }

  for (let c = 0; c < header.length; c++) {
    const len = getTokensTextLength(header[c]);
    if (len > maxLengths[c]) {
      maxLengths[c] = len;
    }
  }

  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    for (let c = 0; c < row.length && c < colCount; c++) {
      const len = getTokensTextLength(row[c]);
      if (len > maxLengths[c]) {
        maxLengths[c] = len;
      }
    }
  }

  const widths: Array<number> = [];
  for (let c = 0; c < colCount; c++) {
    const charLen = maxLengths[c];
    // 每个字符约 8px 宽度（中文约 14px），加上 padding 16px
    // 短内容：最小 50px
    // 中等内容：按字符数计算
    // 长内容：最大 400px，让内容换行
    const estimated = charLen * 10 + 16;
    const minW = 50;
    const maxW = 400;
    if (estimated < minW) {
      widths.push(minW);
    } else if (estimated > maxW) {
      widths.push(maxW);
    } else {
      widths.push(estimated);
    }
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

function parseBlocks(markdown: string): Array<MarkdownBlock> {
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

        const columnWidths = computeColumnWidths(header, rows);
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

@Component
export struct MarkdownView {
  @Prop markdown: string;
  @Prop inlineOnly: boolean = false;
  @Prop fontSize: number = 15;
  @Prop fontColor: number = 0x222222;
  @Prop fontWeight: FontWeight = FontWeight.Normal;
  @Prop theme: AppThemeTokens = getAppThemeTokens('light');

  private mdHeadingColor(): number {
    return this.theme.markdown.headingColor;
  }

  private mdLinkColor(): number {
    return this.theme.markdown.linkColor;
  }

  private mdCodeTextColor(): number {
    return this.theme.markdown.codeTextColor;
  }

  private mdCodeBackgroundColor(): number {
    return this.theme.markdown.codeBackgroundColor;
  }

  private mdTableHeaderBackgroundColor(): number {
    return this.theme.markdown.tableHeaderBackgroundColor;
  }

  private mdTableCellBackgroundColor(): number {
    return this.theme.markdown.tableCellBackgroundColor;
  }

  private mdTableBorderColor(): number {
    return this.theme.markdown.tableBorderColor;
  }

  private tableTextAlign(aligns: Array<MarkdownCellAlign>, colIndex: number): TextAlign {
    const key: MarkdownCellAlign = aligns.length > colIndex ? aligns[colIndex] : 'start';
    if (key === 'center') return TextAlign.Center;
    if (key === 'end') return TextAlign.End;
    return TextAlign.Start;
  }

  @Builder
  private InlineStyled(tokens: Array<MarkdownInlineToken>, color: number, weight: FontWeight, align: TextAlign): void {
    Text() {
      ForEach(tokens, (token: MarkdownInlineToken, index: number) => {
        if (token.kind === 'text') {
          Span(token.text);
        } else if (token.kind === 'bold') {
          Span(token.text).fontWeight(FontWeight.Bold);
        } else if (token.kind === 'italic') {
          Span(token.text).fontStyle(FontStyle.Italic);
        } else if (token.kind === 'code') {
          Span(token.text).fontFamily('monospace').fontColor(this.mdCodeTextColor());
        } else {
          Span(token.text)
            .fontColor(this.mdLinkColor())
            .decoration({ type: TextDecorationType.Underline });
        }
      }, (_: MarkdownInlineToken, index: number) => `${index}`);
    }
    .fontSize(this.fontSize)
    .fontColor(color)
    .fontWeight(weight)
    .textAlign(align)
    .width('100%')
    .maxLines(999)
    .textOverflow({ overflow: TextOverflow.Clip });
  }

  @Builder
  private Inline(tokens: Array<MarkdownInlineToken>): void {
    this.InlineStyled(tokens, this.fontColor, this.fontWeight, TextAlign.Start);
  }

  private headingFontSize(level: number): number {
    if (level <= 1) return this.fontSize + 6;
    if (level === 2) return this.fontSize + 4;
    if (level === 3) return this.fontSize + 2;
    return this.fontSize;
  }

  build() {
    Column({ space: this.inlineOnly ? 0 : 6 }) {
      if (this.inlineOnly) {
        this.Inline(parseInlineTokens(this.markdown ?? ''));
      } else {
        ForEach(parseBlocks(this.markdown ?? ''), (block: MarkdownBlock, index: number) => {
          if (block.kind === 'codeblock') {
            Text(block.code)
              .fontFamily('monospace')
              .fontSize(this.fontSize - 2)
              .fontColor(this.mdCodeTextColor())
              .backgroundColor(this.mdCodeBackgroundColor())
              .borderRadius(10)
              .padding(10)
              .maxLines(999)
              .textOverflow({ overflow: TextOverflow.Clip });
          } else if (block.kind === 'heading') {
            Text() {
              ForEach(block.tokens, (t: MarkdownInlineToken, i2: number) => {
                if (t.kind === 'text') {
                  Span(t.text);
                } else if (t.kind === 'bold') {
                  Span(t.text).fontWeight(FontWeight.Bold);
                } else if (t.kind === 'italic') {
                  Span(t.text).fontStyle(FontStyle.Italic);
                } else if (t.kind === 'code') {
                  Span(t.text).fontFamily('monospace').fontColor(this.mdCodeTextColor());
                } else {
                  Span(t.text).fontColor(this.mdLinkColor()).decoration({ type: TextDecorationType.Underline });
                }
              }, (_: MarkdownInlineToken, i2: number) => `${index}:${i2}`);
            }
            .fontSize(this.headingFontSize(block.level))
            .fontColor(this.mdHeadingColor())
            .fontWeight(FontWeight.Bold)
            .maxLines(999)
            .textOverflow({ overflow: TextOverflow.Clip });
          } else if (block.kind === 'list') {
            Column({ space: 4 }) {
              ForEach(block.items, (item: Array<MarkdownInlineToken>, itemIndex: number) => {
                Row({ space: 8 }) {
                  Text(block.ordered ? `${itemIndex + 1}.` : '\u2022')
                    .fontSize(this.fontSize)
                    .fontColor(this.fontColor);
                  this.Inline(item);
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
                        this.InlineStyled(cell, this.mdHeadingColor(), FontWeight.Bold, this.tableTextAlign(block.aligns, colIndex));
                      }
                      .width(block.columnWidths.length > colIndex ? block.columnWidths[colIndex] : 60)
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .backgroundColor(this.mdTableHeaderBackgroundColor())
                      .borderWidth(1)
                      .borderColor(this.mdTableBorderColor());
                    }, (_: Array<MarkdownInlineToken>, colIndex: number) => `${index}:h:${colIndex}`);
                  }
                }

                ForEach(block.rows, (row: Array<Array<MarkdownInlineToken>>, rowIndex: number) => {
                  Row({ space: 0 }) {
                    ForEach(row, (cell: Array<MarkdownInlineToken>, colIndex: number) => {
                      Column() {
                        this.InlineStyled(cell, this.fontColor, FontWeight.Normal, this.tableTextAlign(block.aligns, colIndex));
                      }
                      .width(block.columnWidths.length > colIndex ? block.columnWidths[colIndex] : 60)
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .backgroundColor(this.mdTableCellBackgroundColor())
                      .borderWidth(1)
                      .borderColor(this.mdTableBorderColor());
                    }, (_: Array<MarkdownInlineToken>, colIndex: number) => `${index}:${rowIndex}:${colIndex}`);
                  }
                }, (_: Array<Array<MarkdownInlineToken>>, rowIndex: number) => `${index}:r:${rowIndex}`);
              }
              .alignItems(HorizontalAlign.Start)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off);
          } else {
            this.Inline(block.tokens);
          }
        }, (_: MarkdownBlock, index: number) => `${index}`);
      }
    }
  }
}
