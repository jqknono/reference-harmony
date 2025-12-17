import util from '@ohos.util';
import type resourceManager from '@ohos.resourceManager';

import type { ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceManifestBundle } from './referenceModels';

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | Array<JsonValue> | object;
interface JsonManifestBundleLike {
  zh?: JsonValue;
  en?: JsonValue;
}

export class ReferenceRepository {
  private readonly decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  private readonly rm: resourceManager.ResourceManager;

  constructor(rm: resourceManager.ResourceManager) {
    this.rm = rm;
  }

  private decodeUtf8(bytes: Uint8Array): string {
    const replacement = 0xfffd;
    let out = '';
    let i = 0;

    while (i < bytes.length) {
      const b0 = bytes[i++];
      if (b0 < 0x80) {
        out += String.fromCharCode(b0);
        continue;
      }

      if (b0 >= 0xc2 && b0 < 0xe0) {
        if (i >= bytes.length) {
          out += String.fromCharCode(replacement);
          break;
        }
        const b1 = bytes[i++];
        if ((b1 & 0xc0) !== 0x80) {
          out += String.fromCharCode(replacement);
          continue;
        }
        out += String.fromCharCode(((b0 & 0x1f) << 6) | (b1 & 0x3f));
        continue;
      }

      if (b0 >= 0xe0 && b0 < 0xf0) {
        if (i + 1 >= bytes.length) {
          out += String.fromCharCode(replacement);
          break;
        }
        const b1 = bytes[i++];
        const b2 = bytes[i++];
        if ((b1 & 0xc0) !== 0x80 || (b2 & 0xc0) !== 0x80) {
          out += String.fromCharCode(replacement);
          continue;
        }
        out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
        continue;
      }

      if (b0 >= 0xf0 && b0 < 0xf5) {
        if (i + 2 >= bytes.length) {
          out += String.fromCharCode(replacement);
          break;
        }
        const b1 = bytes[i++];
        const b2 = bytes[i++];
        const b3 = bytes[i++];
        if ((b1 & 0xc0) !== 0x80 || (b2 & 0xc0) !== 0x80 || (b3 & 0xc0) !== 0x80) {
          out += String.fromCharCode(replacement);
          continue;
        }
        const codePoint = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
        if (codePoint > 0x10ffff) {
          out += String.fromCharCode(replacement);
          continue;
        }
        const cp = codePoint - 0x10000;
        out += String.fromCharCode(0xd800 | ((cp >> 10) & 0x3ff), 0xdc00 | (cp & 0x3ff));
        continue;
      }

      out += String.fromCharCode(replacement);
    }

    return out;
  }

  private async readText(rawPath: string): Promise<string> {
    const rawFile: Uint8Array | ArrayBuffer = await Promise.resolve()
      .then((): Promise<Uint8Array | ArrayBuffer> => this.rm.getRawFileContent(rawPath) as Promise<Uint8Array | ArrayBuffer>)
      .then(
        (value: Uint8Array | ArrayBuffer): Uint8Array | ArrayBuffer => value,
        (e: Error | string): Promise<Uint8Array | ArrayBuffer> =>
          Promise.reject<Uint8Array | ArrayBuffer>(new Error(`读取 rawfile 失败：${rawPath} (${String(e)})`)),
      );

    const bytes: Uint8Array = rawFile instanceof ArrayBuffer
      ? new Uint8Array(rawFile)
      : new Uint8Array(rawFile.buffer.slice(rawFile.byteOffset, rawFile.byteOffset + rawFile.byteLength));

    if (bytes.length === 0) {
      throw new Error(`读取 rawfile 失败：${rawPath} (rawfile 内容为空)`);
    }

    const decodePrimary: Promise<string> = Promise.resolve()
      .then((): string => this.decoder.decodeToString(bytes))
      .then(
        (value: string): string => value,
        (e: Error | string): Promise<string> => Promise.reject<string>(new Error(`rawfile 解码失败：${String(e)}`)),
      );

    let text: string = await decodePrimary;

    if (!text) {
      // Some SDKs treat ArrayBuffer as the real input type; pass buffer while keeping signature compatible.
      const decodeFallback: Promise<string> = Promise.resolve()
        .then((): string => this.decoder.decodeToString(bytes.buffer as Uint8Array))
        .then(
          (value: string): string => value,
          (e: Error | string): Promise<string> => Promise.reject<string>(new Error(`rawfile 解码失败：${String(e)}`)),
        );
      text = await decodeFallback;
    }

    if (!text) {
      text = this.decodeUtf8(bytes);
    }
    if (!text) {
      throw new Error(`读取 rawfile 失败：${rawPath} (rawfile 解码为空 bytes=${bytes.length})`);
    }
    return text;
  }

  private async readJson<T>(rawPath: string): Promise<T> {
    return this.readText(rawPath).then(
      (text: string): Promise<T> =>
        Promise.resolve()
          .then((): T => JSON.parse(text) as T)
          .then(
            (parsed: T): T => parsed,
            (err: Error | string): Promise<T> => Promise.reject<T>(new Error(`解析 JSON 失败：${rawPath} (${String(err)})`)),
          ),
      (err: Error | string): Promise<T> => Promise.reject<T>(new Error(String(err))),
    );
  }

  private asManifest(raw: JsonValue): ReferenceManifest | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const candidate: ReferenceManifest = raw as ReferenceManifest;
    if (!candidate.source || typeof candidate.source !== 'object') return null;
    if (!Array.isArray(candidate.docs)) return null;
    return candidate;
  }

  private asManifestBundle(raw: JsonValue): ReferenceManifestBundle | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const rawBundle = raw as JsonManifestBundleLike;
    const zh = this.asManifest(rawBundle.zh ?? null);
    const en = this.asManifest(rawBundle.en ?? null);
    if (!zh && !en) return null;
    return { zh, en };
  }

  async getManifest(): Promise<ReferenceManifest> {
    return this.getManifestByLang('zh');
  }

  async getManifestByLang(lang: ReferenceLang): Promise<ReferenceManifest> {
    const p = `reference/${lang}/manifest.json`;
    return this.readJson<ReferenceManifest>(p).then(
      (manifest: ReferenceManifest): ReferenceManifest => manifest,
      (primaryErr: Error | string): Promise<ReferenceManifest> => {
        if (lang !== 'zh') {
          return Promise.reject<ReferenceManifest>(new Error(`读取 manifest 失败：${p} (${String(primaryErr)})`));
        }
        return this.readJson<JsonValue>('reference/manifest.json').then(
          (raw: JsonValue): Promise<ReferenceManifest> => {
            const direct = this.asManifest(raw);
            if (direct) return Promise.resolve<ReferenceManifest>(direct);

            const bundle = this.asManifestBundle(raw);
            if (!bundle) {
              return Promise.reject<ReferenceManifest>(new Error(`读取 manifest 失败：reference/manifest.json (格式不匹配)`));
            }
            const picked: ReferenceManifest | null = lang === 'zh' ? bundle.zh : bundle.en;
            const fallback: ReferenceManifest | null = lang === 'zh' ? bundle.en : bundle.zh;
            const pickedManifest: ReferenceManifest | null = picked || fallback;
            if (!pickedManifest) {
              return Promise.reject<ReferenceManifest>(new Error(`读取 manifest 失败：reference/manifest.json (缺少 ${lang} 数据)`));
            }
            return Promise.resolve<ReferenceManifest>(pickedManifest);
          },
          (legacyErr: Error | string): Promise<ReferenceManifest> =>
            Promise.reject<ReferenceManifest>(
              new Error(
                `读取 manifest 失败：${p} (${String(primaryErr)})；兼容路径 reference/manifest.json 也失败 (${String(legacyErr)})`,
              ),
            ),
        );
      },
    );
  }

  async getDoc(docId: string): Promise<ReferenceDoc> {
    return this.getDocByLang('zh', docId);
  }

  async getDocByLang(lang: ReferenceLang, docId: string): Promise<ReferenceDoc> {
    const p = `reference/${lang}/${docId}.json`;
    return this.readJson<ReferenceDoc>(p).then(
      (doc: ReferenceDoc): ReferenceDoc => doc,
      (primaryErr: Error | string): Promise<ReferenceDoc> => {
        if (lang !== 'zh') {
          return Promise.reject<ReferenceDoc>(new Error(`读取文档失败：${p} (${String(primaryErr)})`));
        }
        return this.readJson<ReferenceDoc>(`reference/${docId}.json`).then(
          (legacy: ReferenceDoc): ReferenceDoc => legacy,
          (legacyErr: Error | string): Promise<ReferenceDoc> =>
            Promise.reject<ReferenceDoc>(
              new Error(
                `读取文档失败：${p} (${String(primaryErr)})；兼容路径 reference/${docId}.json 也失败 (${String(legacyErr)})`,
              ),
            ),
        );
      },
    );
  }

  async getDocBySummary(summary: ReferenceDocSummary): Promise<ReferenceDoc> {
    return this.readJson<ReferenceDoc>(summary.file);
  }
}
