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
import { parseMarkdownToDoc } from './onlineMdRepository';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

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

    const markdown = await this.readTextFromUri(fileUri).then(
      (text: string): string => text,
      (err: Error | string): string => {
        throw new Error(String(err));
      },
    );

    if (!markdown.trim()) {
      return { success: false, error: '文件内容为空' };
    }

    const docId = this.extractIdFromUri(fileUri);
    const doc = parseMarkdownToDoc(markdown, docId, fileUri);

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
      cardCount: doc.cards.length,
    };

    return { success: true, doc, summary };
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
    const pathOrUri = normalizeFileUriToPath(uri);
    const path = stripQueryAndFragment(pathOrUri);
    if (!path) return '';

    const stat = await Promise.resolve()
      .then((): Promise<fs.Stat> => fs.stat(path))
      .then(
        (s: fs.Stat): fs.Stat => s,
        (e: Error | string): Promise<fs.Stat> => Promise.reject<fs.Stat>(new Error(`读取文件信息失败：${String(e)}`)),
      );

    const size: number = stat.size;
    if (!Number.isFinite(size) || size <= 0) {
      return '';
    }

    const file = await Promise.resolve()
      .then(() => fs.open(path, fs.OpenMode.READ_ONLY))
      .then(
        (f: fs.File): fs.File => f,
        (e: Error | string): Promise<fs.File> => Promise.reject<fs.File>(new Error(`打开文件失败：${String(e)}`)),
      );

    const buf = new ArrayBuffer(size);
    const readLen: number = await Promise.resolve()
      .then((): Promise<number> => fs.read(file.fd, buf, { offset: 0, length: size }))
      .then(
        (n: number): number => n,
        (e: Error | string): Promise<number> => Promise.reject<number>(new Error(`读取文件失败：${String(e)}`)),
      );

    await Promise.resolve()
      .then(() => fs.close(file.fd))
      .then((): void => undefined, (): void => undefined);

    const bytes = new Uint8Array(buf, 0, Math.max(0, Math.min(readLen, size)));
    return this.decoder.decodeToString(bytes);
  }
}


