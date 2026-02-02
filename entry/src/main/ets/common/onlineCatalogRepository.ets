/**
 * 在线清单列表：从后端拉取可用 Markdown 清单索引（用于“目录”展示）
 */
import http from '@ohos.net.http';
import type { ReferenceDocSummary, ReferenceLang } from './referenceModels';

interface OnlineCatalogItemLike {
  id?: string;
  mdUrl?: string;
  name?: string;
  title?: string;
  icon?: string;
  lang?: string;
  size?: number;
  mtimeIso?: string;
  sectionCount?: number;
  cardCount?: number;
}

interface OnlineCatalogResponseLike {
  version?: number;
  builtAt?: string;
  items?: Array<OnlineCatalogItemLike>;
}

export class OnlineCatalogRepository {
  private static readonly DEFAULT_API_URL: string = 'https://reference.jqknono.com/api/v1/catalog';

  private normalizeApiUrl(apiUrlOrOrigin: string): string {
    let raw: string = String(apiUrlOrOrigin ?? '').trim();
    if (!raw) raw = OnlineCatalogRepository.DEFAULT_API_URL.trim();

    if (!/^https?:\/\//.test(raw)) {
      raw = `http://${raw}`;
    }

    raw = raw.replace(/\/+$/g, '');
    if (/\/api\/v1\/catalog$/i.test(raw)) return raw;
    return `${raw}/api/v1/catalog`;
  }

  private buildUrl(lang: ReferenceLang, apiUrlOrOriginOverride?: string): string {
    const base = this.normalizeApiUrl(apiUrlOrOriginOverride ?? OnlineCatalogRepository.DEFAULT_API_URL).replace(/\/+$/g, '');
    const join = base.includes('?') ? '&' : '?';
    return `${base}${join}lang=${lang}`;
  }

  async fetchCatalog(lang: ReferenceLang, apiUrlOrOriginOverride?: string): Promise<Array<ReferenceDocSummary>> {
    const url = this.buildUrl(lang, apiUrlOrOriginOverride);
    const httpRequest = http.createHttp();

    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'QuickReference-HarmonyOS',
        'Accept': 'application/json',
      },
      connectTimeout: 15000,
      readTimeout: 30000,
    };

    return Promise.resolve()
      .then((): Promise<http.HttpResponse> => httpRequest.request(url, requestOptions))
      .then(
        (response: http.HttpResponse): Promise<Array<ReferenceDocSummary>> => {
          httpRequest.destroy();
          if (response.responseCode !== 200) {
            return Promise.reject<Array<ReferenceDocSummary>>(new Error(`HTTP ${response.responseCode}`));
          }
          const rawText = String(response.result ?? '');
          if (!rawText.trim()) {
            return Promise.reject<Array<ReferenceDocSummary>>(new Error('返回内容为空'));
          }
          return Promise.resolve()
            .then((): OnlineCatalogResponseLike => JSON.parse(rawText) as OnlineCatalogResponseLike)
            .then(
              (parsed: OnlineCatalogResponseLike): Array<ReferenceDocSummary> => {
                const items = Array.isArray(parsed.items) ? parsed.items : [];
                const out: Array<ReferenceDocSummary> = [];
                for (let i = 0; i < items.length; i++) {
                  const it = items[i];
                  const id = String(it?.id ?? '').trim();
                  const mdUrl = String(it?.mdUrl ?? '').trim();
                  if (!id || !mdUrl) continue;
                  const name = String(it?.name ?? '').trim();
                  const title = String(it?.title ?? '').trim();
                  const icon = String(it?.icon ?? '').trim();
                  const sectionCountRaw = Number(it?.sectionCount ?? 0);
                  const cardCountRaw = Number(it?.cardCount ?? 0);
                  const sectionCount = Number.isFinite(sectionCountRaw) && sectionCountRaw > 0 ? Math.floor(sectionCountRaw) : 0;
                  const cardCount = Number.isFinite(cardCountRaw) && cardCountRaw > 0 ? Math.floor(cardCountRaw) : 0;
                  out.push({
                    id: id,
                    name: name || title || id,
                    title: title || name || id,
                    icon: icon || undefined,
                    file: `cloud:${mdUrl}`,
                    sectionCount: sectionCount,
                    cardCount: cardCount,
                  });
                }
                return out;
              },
              (e: Error | string): Promise<Array<ReferenceDocSummary>> =>
                Promise.reject<Array<ReferenceDocSummary>>(new Error(`解析 JSON 失败：${String(e)}`)),
            );
        },
        (e: Error | string): Promise<Array<ReferenceDocSummary>> => {
          httpRequest.destroy();
          return Promise.reject<Array<ReferenceDocSummary>>(new Error(String(e)));
        },
      );
  }
}
