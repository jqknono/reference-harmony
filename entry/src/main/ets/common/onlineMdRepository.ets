/**
 * 在线 Markdown 链接的存储和管理
 */
import preferences from '@ohos.data.preferences';
import http from '@ohos.net.http';
import type { Context } from '@ohos.abilityAccessCtrl';
import type { OnlineMdLink, OnlineMdLinkList } from './onlineMdModels';
import { generateOnlineMdId } from './onlineMdModels';
import type { ReferenceDoc, ReferenceDocSummary, ReferenceSection, ReferenceCardData, ReferenceDocSource } from './referenceModels';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

export interface ParseResult {
  success: boolean;
  doc?: ReferenceDoc;
  summary?: ReferenceDocSummary;
  error?: string;
}

function stripUrlQueryAndFragment(rawUrl: string): string {
  const s = (rawUrl ?? '').trim();
  if (!s) return '';
  const q = s.indexOf('?');
  const h = s.indexOf('#');
  let end = s.length;
  if (q !== -1 && q < end) end = q;
  if (h !== -1 && h < end) end = h;
  let base = s.slice(0, end);
  while (base.endsWith('/')) base = base.slice(0, -1);
  return base;
}

function isMdUrl(rawUrl: string): boolean {
  const base = stripUrlQueryAndFragment(rawUrl).toLowerCase();
  return !!base && base.endsWith('.md');
}

function cleanHeadingText(text: string): string {
  return text.replace(/\\<\s*\/\s*>\s*/g, '').replace(/\s*\{[^}]*\}\s*$/, '').trim();
}

function isTableSeparatorLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed.includes('|')) return false;
  if (/[^|\s:-]/.test(trimmed)) return false;
  const cells = splitTableRow(trimmed);
  if (cells.length === 0) return false;
  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i];
    const c = cell.replace(/\s+/g, '');
    if (!/^:?-{3,}:?$/.test(c)) return false;
  }
  return true;
}

function splitTableRow(line: string): Array<string> {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c: string): string => c.trim());
}

function isListItem(line: string): boolean {
  return /^\s*([-*+]|(\d+\.))\s+/.test(line);
}

function stripListMarker(line: string): string {
  return line.replace(/^\s*([-*+]|(\d+\.))\s+/, '').trim();
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

function getSetextHeading(lines: Array<string>, i: number): SetextHeadingInfo | undefined {
  if (i + 1 >= lines.length) return undefined;
  const text = (lines[i] ?? '').trim();
  if (!text) return undefined;
  const underline = (lines[i + 1] ?? '').trim();
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

interface FenceInfo {
  marker: string;
  lang: string;
  info: string;
}

interface SetextHeadingInfo {
  level: number;
  text: string;
}

interface FrontmatterExtractResult {
  frontmatter: Frontmatter;
  body: string;
}

interface DocNameAndTitle {
  name: string;
  title: string;
}

interface Frontmatter {
  title?: string;
  intro?: string;
  icon?: string;
  background?: string;
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
    const line = lines[i];
    if (!line) continue;
    if (isRehypeIgnoreStart(line)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(line)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (/^\s*<!--/.test(line)) continue;
    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(lines[i], fence.marker)) i++;
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
    const line = lines[i];
    if (!line) continue;
    if (isRehypeIgnoreStart(line)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(line)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (/^\s*<!--/.test(line)) continue;

    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(lines[i], fence.marker)) i++;
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

export function parseMarkdownToDoc(markdown: string, id: string, url: string): ReferenceDoc {
  const fmResult = extractFrontmatter(markdown);
  const frontmatter = fmResult.frontmatter;
  const body = fmResult.body;
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const meta = extractDocNameAndTitle(frontmatter, body, id);
  const title = meta.title;
  const name = meta.name;
  const introTitle = '简介';

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
    const line = lines[i];
    if (isRehypeIgnoreStart(line)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(line)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (/^\s*<!--/.test(line)) continue;
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
        while (i < lines.length && !isFenceClose(lines[i], fence.marker)) i++;
        continue;
      }
      const codeParts: Array<string> = [];

      const skipBetweenFences = (l: string): boolean =>
        !l.trim()
        || /^\s*\{[.#][^}]+\}\s*$/.test(l)
        || isHorizontalRuleLine(l)
        || (/^\s*<!--/.test(l) && !isRehypeIgnoreStart(l) && !isRehypeIgnoreEnd(l));

      while (i < lines.length) {
        const openFence = parseFenceOpen(lines[i]);
        if (!openFence) break;
        const fenceOpenLine = lines[i];
        const buf: Array<string> = [];
        i++;
        while (i < lines.length && !isFenceClose(lines[i], openFence.marker)) {
          buf.push(lines[i]);
          i++;
        }
        const fenceCloseLine = i < lines.length ? lines[i] : openFence.marker;
        const codeBlock = `${fenceOpenLine}\n${buf.join('\n')}\n${fenceCloseLine}`;
        codeParts.push(codeBlock);

        let j = i + 1;
        while (j < lines.length && skipBetweenFences(lines[j])) j++;
        const nextFence = j < lines.length ? parseFenceOpen(lines[j]) : undefined;
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
      const buf = [line.trimEnd(), lines[i + 1].trimEnd()];
      i += 2;
      while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
        buf.push(lines[i].trimEnd());
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
      while (i < lines.length && isListItem(lines[i])) {
        items.push(`• ${stripListMarker(lines[i])}`);
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
      while (i < lines.length && lines[i].trim()) {
        if (getSetextHeading(lines, i)) break;
        if (/^#{1,6}\s+/.test(lines[i])) break;
        if (isListItem(lines[i])) break;
        if (parseFenceOpen(lines[i])) break;
        if (isHorizontalRuleLine(lines[i])) break;
        if (!/^\s*\{[.#][^}]+\}\s*$/.test(lines[i])) buf.push(lines[i].trim());
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

export class OnlineMdRepository {
  private static readonly PREFS_NAME = 'online_md_links';
  private static readonly LINKS_KEY = 'links';

  static isMarkdownUrl(url: string): boolean {
    return isMdUrl(url);
  }

  async getLinks(context: Context): Promise<Array<OnlineMdLink>> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, OnlineMdRepository.PREFS_NAME))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return [];

    const raw: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(OnlineMdRepository.LINKS_KEY, '[]'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : '[]'),
        (): string => '[]',
      );

    const parsed: OnlineMdLinkList = JSON.parse(raw) as OnlineMdLinkList;
    return parsed.links ?? [];
  }

  async saveLinks(context: Context, links: Array<OnlineMdLink>): Promise<void> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, OnlineMdRepository.PREFS_NAME))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;

    const data: OnlineMdLinkList = { links: links };
    await Promise.resolve()
      .then((): Promise<void> => prefs.put(OnlineMdRepository.LINKS_KEY, JSON.stringify(data)))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  async addLink(context: Context, url: string, name: string): Promise<OnlineMdLink> {
    const links = await this.getLinks(context);
    const newLink: OnlineMdLink = {
      id: generateOnlineMdId(),
      url: url,
      name: name,
      addedTime: Date.now(),
    };
    links.push(newLink);
    await this.saveLinks(context, links);
    return newLink;
  }

  async removeLink(context: Context, id: string): Promise<void> {
    const links = await this.getLinks(context);
    const filtered = links.filter((link: OnlineMdLink): boolean => link.id !== id);
    await this.saveLinks(context, filtered);
  }

  async fetchAndParse(url: string): Promise<ParseResult> {
    if (!isMdUrl(url)) {
      const baseUrl = stripUrlQueryAndFragment(url);
      return {
        success: false,
        error: baseUrl
          ? `仅支持 Markdown 文件（仅允许 .md 后缀）：${baseUrl}`
          : '仅支持 Markdown 文件（仅允许 .md 后缀）',
      };
    }

    const httpRequest = http.createHttp();
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'QuickReference-HarmonyOS',
        'Accept': 'text/plain, text/markdown, */*',
      },
      connectTimeout: 30000,
      readTimeout: 60000,
    };
    // 该 API 可能同步抛异常（ArkTS 编译器会要求显式处理）
    let responsePromise: Promise<http.HttpResponse>;
    try {
      responsePromise = httpRequest.request(url, requestOptions);
    } catch (e) {
      httpRequest.destroy();
      return {
        success: false,
        error: String(e),
      };
    }

    return responsePromise.then(
      (response: http.HttpResponse): ParseResult => {
        httpRequest.destroy();
        if (response.responseCode !== 200) {
          const errorResult: ParseResult = {
            success: false,
            error: `HTTP ${response.responseCode}`,
          };
          return errorResult;
        }

        const markdown = String(response.result ?? '');
        if (!markdown.trim()) {
          const emptyResult: ParseResult = {
            success: false,
            error: '获取的内容为空',
          };
          return emptyResult;
        }

        const id = this.extractIdFromUrl(url);
        const doc = parseMarkdownToDoc(markdown, id, url);

        const summary: ReferenceDocSummary = {
          id: doc.id,
          name: doc.name,
          title: doc.title,
          file: `online:${url}`,
          sectionCount: doc.sections.length,
          cardCount: doc.cards.length,
        };

        const successResult: ParseResult = {
          success: true,
          doc: doc,
          summary: summary,
        };
        return successResult;
      },
      (error: Error | string): ParseResult => {
        httpRequest.destroy();
        const failResult: ParseResult = {
          success: false,
          error: String(error),
        };
        return failResult;
      },
    );
  }

  private extractIdFromUrl(url: string): string {
    const cleanUrl = stripUrlQueryAndFragment(url);
    const parts = (cleanUrl || url).split('/');
    let fileName = parts[parts.length - 1] ?? 'online';
    if (fileName.toLowerCase().endsWith('.md')) {
      fileName = fileName.slice(0, -3);
    }
    const normalized = fileName.normalize('NFKD').replace(/[^\w-]/g, '_');
    return `online_${normalized.replace(/_+/g, '_').replace(/^_+|_+$/g, '') || 'doc'}`;
  }

  async getDocFromCache(context: Context, linkId: string): Promise<ReferenceDoc | undefined> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, `online_doc_${linkId}`))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return undefined;

    const raw: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('doc', ''))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : ''),
        (): string => '',
      );

    if (!raw) return undefined;
    return JSON.parse(raw) as ReferenceDoc;
  }

  async saveDocToCache(context: Context, linkId: string, doc: ReferenceDoc): Promise<void> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, `online_doc_${linkId}`))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;

    await Promise.resolve()
      .then((): Promise<void> => prefs.put('doc', JSON.stringify(doc)))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  async deleteDocCache(context: Context, linkId: string): Promise<void> {
    await Promise.resolve()
      .then((): Promise<void> => preferences.deletePreferences(context, `online_doc_${linkId}`))
      .then((): void => undefined, (): void => undefined);
  }
}

