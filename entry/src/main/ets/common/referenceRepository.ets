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
      const rawFile: Uint8Array | ArrayBuffer = await this.rm.getRawFileContent(rawPath) as Uint8Array | ArrayBuffer;
      const bytes: Uint8Array = rawFile instanceof ArrayBuffer ? new Uint8Array(rawFile) : rawFile;
      if (bytes.length === 0) {
        throw new Error('rawfile 内容为空');
      }
      const text: string = this.decoder.decodeToString(bytes);
      if (!text) {
        throw new Error(`rawfile 解码为空 (bytes=${bytes.length})`);
      }
      return text;
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

  async getManifest(): Promise<ReferenceManifest> {
    return this.getManifestByLang('zh');
  }

  async getManifestByLang(lang: ReferenceLang): Promise<ReferenceManifest> {
    const p = `reference/${lang}/manifest.json`;
    try {
      return await this.readJson<ReferenceManifest>(p);
    } catch (primaryErr) {
      // backward-compat: old single-language location
      if (lang === 'zh') {
        try {
          return await this.readJson<ReferenceManifest>('reference/manifest.json');
        } catch (legacyErr) {
          throw new Error(
            `读取 manifest 失败：${p} (${String(primaryErr)})；兼容路径 reference/manifest.json 也失败 (${String(legacyErr)})`,
          );
        }
      }

      throw new Error(`读取 manifest 失败：${p} (${String(primaryErr)})`);
    }
  }

  async getDoc(docId: string): Promise<ReferenceDoc> {
    return this.getDocByLang('zh', docId);
  }

  async getDocByLang(lang: ReferenceLang, docId: string): Promise<ReferenceDoc> {
    const p = `reference/${lang}/${docId}.json`;
    try {
      return await this.readJson<ReferenceDoc>(p);
    } catch (primaryErr) {
      // backward-compat: old single-language location
      if (lang === 'zh') {
        try {
          return await this.readJson<ReferenceDoc>(`reference/${docId}.json`);
        } catch (legacyErr) {
          throw new Error(
            `读取文档失败：${p} (${String(primaryErr)})；兼容路径 reference/${docId}.json 也失败 (${String(legacyErr)})`,
          );
        }
      }

      throw new Error(`读取文档失败：${p} (${String(primaryErr)})`);
    }
  }

  async getDocBySummary(summary: ReferenceDocSummary): Promise<ReferenceDoc> {
    return this.readJson<ReferenceDoc>(summary.file);
  }
}
