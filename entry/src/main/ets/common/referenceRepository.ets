import util from '@ohos.util';
import type resourceManager from '@ohos.resourceManager';

import type { ReferenceDoc, ReferenceDocSummary, ReferenceManifest } from './referenceModels';

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

  async getManifest(): Promise<ReferenceManifest> {
    return this.readJson<ReferenceManifest>('reference/manifest.json');
  }

  async getDoc(docId: string): Promise<ReferenceDoc> {
    return this.readJson<ReferenceDoc>(`reference/${docId}.json`);
  }

  async getDocBySummary(summary: ReferenceDocSummary): Promise<ReferenceDoc> {
    return this.readJson<ReferenceDoc>(summary.file);
  }
}
