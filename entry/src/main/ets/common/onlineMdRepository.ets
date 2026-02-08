/**
 * 在线 Markdown 链接的存储和管理
 */
import preferences from '@ohos.data.preferences';
import http from '@ohos.net.http';
import type { Context } from '@ohos.abilityAccessCtrl';
import type { OnlineMdLink, OnlineMdLinkList } from './onlineMdModels';
import { generateOnlineMdId } from './onlineMdModels';
import type { ReferenceDoc, ReferenceDocSummary, ReferenceSection, ReferenceCardData, ReferenceDocSource } from './referenceModels';
import { countMarkdownTableRows, parseMarkdownToDoc } from './markdownDocParser';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

export interface ParseResult {
  success: boolean;
  doc?: ReferenceDoc;
  summary?: ReferenceDocSummary;
  error?: string;
}

function looksLikeHtmlDocument(text: string): boolean {
  const t = String(text ?? '').trimStart();
  if (!t) return false;
  // 强特征：HTML 文档声明/根元素。用于拦截 GitHub blob 等返回的网页内容。
  if (/^<!doctype\s+html/i.test(t)) return true;
  if (/^<html(\s|>)/i.test(t)) return true;
  // 兼容某些站点没有 doctype，但有 head/meta/title 等结构
  if (/^<head(\s|>)/i.test(t)) return true;
  if (/^<meta(\s|>)/i.test(t)) return true;
  if (/^<title(\s|>)/i.test(t)) return true;
  return false;
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
  return !!base && (base.endsWith('.md') || base.endsWith('.markdown'));
}

function cleanHeadingText(text: string): string {
  return text.replace(/\\<\s*\/\s*>\s*/g, '').replace(/\s*\{[^}]*\}\s*$/, '').trim();
}

function stripHtmlCommentsInLine(line: string): string {
  // 移除 HTML 注释（含 rehype 指令），例如: <!-- ... -->
  // 仅用于普通文本行；代码围栏内部的内容会被整体保留。
  return String(line ?? '').replace(/<!--[\s\S]*?-->/g, '');
}

function isTableSeparatorLine(line: string): boolean {
  const trimmed = stripHtmlCommentsInLine(line).trim();
  if (!trimmed.includes('|')) return false;
  if (/[^|\s:-]/.test(trimmed)) return false;
  const cells = splitTableRow(trimmed);
  if (cells.length < 2) return false;
  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i];
    const c = cell.replace(/\s+/g, '');
    if (!c) return false;
    let hasDash = false;
    for (let j = 0; j < c.length; j++) {
      const ch = c.charAt(j);
      if (ch === '-') hasDash = true;
      if (ch !== '-' && ch !== ':') return false;
    }
    if (!hasDash) return false;
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
          ? `仅支持 Markdown 文件（仅允许 .md/.markdown 后缀）：${baseUrl}`
          : '仅支持 Markdown 文件（仅允许 .md/.markdown 后缀）',
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

        if (looksLikeHtmlDocument(markdown)) {
          const hint = url.includes('github.com') && url.includes('/blob/')
            ? '看起来你使用的是 GitHub 的 blob 页面链接，请改用 raw 直链（raw.githubusercontent.com）'
            : '返回内容疑似网页 HTML，请确认链接指向的是原始 .md 文件内容（raw 直链）';
          const htmlResult: ParseResult = {
            success: false,
            error: hint,
          };
          return htmlResult;
        }

        const id = this.extractIdFromUrl(url);
        const doc = parseMarkdownToDoc(markdown, id, url);
        const tableRows = countMarkdownTableRows(markdown);

        const summary: ReferenceDocSummary = {
          id: doc.id,
          name: doc.name,
          title: doc.title,
          file: `online:${url}`,
          sectionCount: doc.sections.length,
          cardCount: tableRows > 0 ? tableRows : doc.cards.length,
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
    const lower = fileName.toLowerCase();
    if (lower.endsWith('.md')) {
      fileName = fileName.slice(0, -3);
    } else if (lower.endsWith('.markdown')) {
      fileName = fileName.slice(0, -'.markdown'.length);
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
