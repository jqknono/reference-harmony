import util from '@ohos.util';
import type resourceManager from '@ohos.resourceManager';

import type { ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest } from './referenceModels';

export class ReferenceRepository {
  private readonly decoder: util.TextDecoder = new util.TextDecoder();
  private readonly rm: resourceManager.ResourceManager;

  constructor(rm: resourceManager.ResourceManager) {
    this.rm = rm;
  }

  private async readText(rawPath: string): Promise<string> {
    try {
      const bytes = await this.rm.getRawFileContent(rawPath);
      return this.decoder.decodeToString(bytes);
    } catch (e) {
      throw new Error(`读取 rawfile 失败：${rawPath} (${String(e)})`);
    }
  }

  private async readJson<T>(rawPath: string): Promise<T> {
    const text = await this.readText(rawPath);
    try {
      return JSON.parse(text) as T;
    } catch (e) {
      throw new Error(`解析 JSON 失败：${rawPath} (${String(e)})`);
    }
  }

  private async tryReadJson<T>(rawPath: string): Promise<T | undefined> {
    try {
      return await this.readJson<T>(rawPath);
    } catch {
      return undefined;
    }
  }

  async getManifest(): Promise<ReferenceManifest> {
    return this.getManifestByLang('zh');
  }

  async getManifestByLang(lang: ReferenceLang): Promise<ReferenceManifest> {
    const p = `reference/${lang}/manifest.json`;
    const primary = await this.tryReadJson<ReferenceManifest>(p);
    if (primary !== undefined) return primary;

    // backward-compat: old single-language location
    if (lang === 'zh') {
      return await this.readJson<ReferenceManifest>('reference/manifest.json');
    }

    throw new Error(`读取 manifest 失败：${p}`);
  }

  async getDoc(docId: string): Promise<ReferenceDoc> {
    return this.getDocByLang('zh', docId);
  }

  async getDocByLang(lang: ReferenceLang, docId: string): Promise<ReferenceDoc> {
    const p = `reference/${lang}/${docId}.json`;
    const primary = await this.tryReadJson<ReferenceDoc>(p);
    if (primary !== undefined) return primary;

    // backward-compat: old single-language location
    if (lang === 'zh') {
      return await this.readJson<ReferenceDoc>(`reference/${docId}.json`);
    }

    throw new Error(`读取文档失败：${p}`);
  }

  async getDocBySummary(summary: ReferenceDocSummary): Promise<ReferenceDoc> {
    return this.readJson<ReferenceDoc>(summary.file);
  }
}
