/**
 * 本地 Markdown 文件的存储与解析
 */
import preferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import type { Context } from '@ohos.abilityAccessCtrl';
import type { OnlineMdLink, OnlineMdLinkList } from './onlineMdModels';
import type { ReferenceDoc, ReferenceDocSummary, ReferenceDocSource } from './referenceModels';
import type { ParseResult } from './onlineMdRepository';
import { countMarkdownTableRows, parseMarkdownToDoc } from './markdownDocParser';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

interface ReadTextResult {
  text: string;
  error: string;
}

interface StatAttemptResult {
  ok: boolean;
  stat: fs.Stat | null;
  error: string;
}

interface OpenAttemptResult {
  ok: boolean;
  fd: number;
  error: string;
}

interface ReadAttemptResult {
  ok: boolean;
  n: number;
  error: string;
}

function stripQueryAndFragment(raw: string): string {
  const s = (raw ?? '').trim();
  if (!s) return '';
  const q = s.indexOf('?');
  const h = s.indexOf('#');
  let end = s.length;
  if (q !== -1 && q < end) end = q;
  if (h !== -1 && h < end) end = h;
  return s.slice(0, end);
}

function normalizeFileUriToPath(uri: string): string {
  const s = (uri ?? '').trim();
  if (s.startsWith('file://')) {
    return s.slice('file://'.length);
  }
  return s;
}

function generateLocalMdId(): string {
  return `local_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
}

export class LocalMdRepository {
  private static readonly PREFS_NAME = 'local_md_links';
  private static readonly LINKS_KEY = 'links';
  private readonly decoder: util.TextDecoder = new util.TextDecoder('utf-8');

  async getLinks(context: Context): Promise<Array<OnlineMdLink>> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, LocalMdRepository.PREFS_NAME))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return [];

    const raw: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(LocalMdRepository.LINKS_KEY, '[]'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : '[]'),
        (): string => '[]',
      );

    const parsed: OnlineMdLinkList = JSON.parse(raw) as OnlineMdLinkList;
    return parsed.links ?? [];
  }

  async saveLinks(context: Context, links: Array<OnlineMdLink>): Promise<void> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, LocalMdRepository.PREFS_NAME))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;

    const data: OnlineMdLinkList = { links: links };
    await Promise.resolve()
      .then((): Promise<void> => prefs.put(LocalMdRepository.LINKS_KEY, JSON.stringify(data)))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  async addLink(context: Context, uri: string, name: string): Promise<OnlineMdLink> {
    const links = await this.getLinks(context);
    const trimmed = (uri ?? '').trim();
    for (let i = 0; i < links.length; i++) {
      if ((links[i]?.url ?? '').trim() === trimmed) {
        // 已存在：仅更新名称（如果传入更好）
        if (name && name.trim() && links[i].name !== name) {
          links[i].name = name;
          await this.saveLinks(context, links);
        }
        return links[i];
      }
    }

    const newLink: OnlineMdLink = {
      id: generateLocalMdId(),
      url: uri,
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

  async readAndParse(uri: string): Promise<ParseResult> {
    const fileUri = (uri ?? '').trim();
    if (!fileUri) {
      return { success: false, error: '文件路径为空' };
    }

    const readResult = await Promise.resolve()
      .then((): Promise<string> => this.readTextFromUri(fileUri))
      .then(
        (text: string): ReadTextResult => ({ text: text, error: '' }),
        (err: Error | string): ReadTextResult => ({ text: '', error: String(err) }),
      );
    if (readResult.error) {
      return { success: false, error: readResult.error };
    }
    const markdown = readResult.text;

    if (!markdown.trim()) {
      return { success: false, error: '文件内容为空' };
    }

    const docId = this.extractIdFromUri(fileUri);
    const doc = parseMarkdownToDoc(markdown, docId, fileUri);
    const tableRows = countMarkdownTableRows(markdown);

    const source: ReferenceDocSource = {
      repo: fileUri,
      path: fileUri,
      ref: 'local',
      url: fileUri,
      lang: doc.source?.lang,
      mode: 'local',
    };
    doc.source = source;

    const summary: ReferenceDocSummary = {
      id: doc.id,
      name: doc.name,
      title: doc.title,
      file: `local:${fileUri}`,
      sectionCount: doc.sections.length,
      cardCount: tableRows > 0 ? tableRows : doc.cards.length,
    };

    return { success: true, doc, summary };
  }

  // Read raw markdown text from a local file URI/path (no parsing).
  async readText(uri: string): Promise<string> {
    return this.readTextFromUri((uri ?? '').trim());
  }

  async getDocFromCache(context: Context, linkId: string): Promise<ReferenceDoc | undefined> {
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, `local_doc_${linkId}`))
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
      .then((): Promise<Preferences> => preferences.getPreferences(context, `local_doc_${linkId}`))
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
      .then((): Promise<void> => preferences.deletePreferences(context, `local_doc_${linkId}`))
      .then((): void => undefined, (): void => undefined);
  }

  private extractIdFromUri(uri: string): string {
    const clean = stripQueryAndFragment(uri);
    const parts = clean.split('/');
    let fileName = parts[parts.length - 1] ?? 'local';
    const lower = fileName.toLowerCase();
    if (lower.endsWith('.md')) {
      fileName = fileName.slice(0, -3);
    } else if (lower.endsWith('.markdown')) {
      fileName = fileName.slice(0, -'.markdown'.length);
    }
    const normalized = fileName.normalize('NFKD').replace(/[^\w-]/g, '_');
    return `localdoc_${normalized.replace(/_+/g, '_').replace(/^_+|_+$/g, '') || 'doc'}`;
  }

  private async readTextFromUri(uri: string): Promise<string> {
    const rawUri = stripQueryAndFragment((uri ?? '').trim());
    if (!rawUri) return '';
    const rawPathOrUri = normalizeFileUriToPath(rawUri);
    const strippedPath = stripQueryAndFragment(rawPathOrUri);

    const candidates: Array<string> = [];
    if (strippedPath) candidates.push(strippedPath);
    if (rawUri && rawUri !== strippedPath) candidates.push(rawUri);
    if (candidates.length === 0) return '';

    let fileFd: number = -1;
    let lastOpenError = '';
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      const openResult = await Promise.resolve()
        .then((): Promise<fs.File> => fs.open(candidate, fs.OpenMode.READ_ONLY))
        .then(
          (f: fs.File): OpenAttemptResult => ({ ok: true, fd: f.fd, error: '' }),
          (e: Error | string): OpenAttemptResult => ({ ok: false, fd: -1, error: `打开文件失败：${String(e)}` }),
        );
      if (openResult.ok && openResult.fd >= 0) {
        fileFd = openResult.fd;
        lastOpenError = '';
        break;
      }
      lastOpenError = openResult.error;
    }
    if (fileFd < 0) {
      return Promise.reject(new Error(lastOpenError || '打开文件失败'));
    }

    const chunkSize = 64 * 1024;
    const chunks: Array<Uint8Array> = [];
    let total = 0;
    let position = 0;

    const readAll = async (): Promise<string> => {
      while (true) {
        const buf = new ArrayBuffer(chunkSize);
        const readResult = await Promise.resolve()
          .then((): Promise<number> => fs.read(fileFd, buf, { offset: position, length: chunkSize }))
          .then(
            (n: number): ReadAttemptResult => ({ ok: true, n: n, error: '' }),
            (e: Error | string): ReadAttemptResult => ({ ok: false, n: 0, error: `读取文件失败：${String(e)}` }),
          );
        if (!readResult.ok) {
          return Promise.reject(new Error(readResult.error || '读取文件失败'));
        }
        if (readResult.n <= 0) {
          break;
        }

        const view = new Uint8Array(buf, 0, readResult.n);
        const copy = new Uint8Array(readResult.n);
        copy.set(view);
        chunks.push(copy);
        total += readResult.n;
        position += readResult.n;
      }

      if (total <= 0) return '';

      const merged = new Uint8Array(total);
      let offset = 0;
      for (let i = 0; i < chunks.length; i++) {
        const c = chunks[i];
        merged.set(c, offset);
        offset += c.length;
      }
      return this.decoder.decodeToString(merged);
    };

    return Promise.resolve()
      .then((): Promise<string> => readAll())
      .then(
        (text: string): Promise<string> =>
          Promise.resolve()
            .then((): Promise<void> => fs.close(fileFd))
            .then((): string => text, (): string => text),
        (e: Error | string): Promise<string> =>
          Promise.resolve()
            .then((): Promise<void> => fs.close(fileFd))
            .then(
              (): Promise<string> => Promise.reject<string>(e),
              (): Promise<string> => Promise.reject<string>(e),
            ),
      );
  }
}
