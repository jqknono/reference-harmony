import http from '@ohos.net.http';

interface ShareCreateResponseLike {
  id?: string;
  url?: string;
  deepLink?: string;
}

interface ShareGetResponseLike {
  id?: string;
  data?: string;
}

export interface ShareCreateResult {
  id: string;
  url: string;
  deepLink: string;
}

export class OnlineShareRepository {
  private static readonly DEFAULT_API_URL: string = 'https://reference.jqknono.com/api/v1/share';

  private normalizeApiUrl(apiUrlOrOrigin: string): string {
    let raw: string = String(apiUrlOrOrigin ?? '').trim();
    if (!raw) raw = OnlineShareRepository.DEFAULT_API_URL.trim();

    if (!/^https?:\/\//.test(raw)) {
      raw = `http://${raw}`;
    }

    raw = raw.replace(/\/+$/g, '');
    if (/\/api\/v1\/share$/i.test(raw)) return raw;
    return `${raw}/api/v1/share`;
  }

  private createUrl(apiUrlOrOriginOverride?: string): string {
    return this.normalizeApiUrl(apiUrlOrOriginOverride ?? OnlineShareRepository.DEFAULT_API_URL);
  }

  private getUrl(shareId: string, apiUrlOrOriginOverride?: string): string {
    const base = this.normalizeApiUrl(apiUrlOrOriginOverride ?? OnlineShareRepository.DEFAULT_API_URL).replace(/\/+$/g, '');
    const id = encodeURIComponent(String(shareId ?? '').trim());
    return `${base}/${id}`;
  }

  async createShare(data: string, apiUrlOrOriginOverride?: string): Promise<ShareCreateResult> {
    const url = this.createUrl(apiUrlOrOriginOverride);
    const httpRequest = http.createHttp();

    const body = JSON.stringify({ data: String(data ?? '') });
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'User-Agent': 'QuickReference-HarmonyOS',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 30000,
    };

    return Promise.resolve()
      .then((): Promise<http.HttpResponse> => httpRequest.request(url, requestOptions))
      .then(
        (response: http.HttpResponse): Promise<ShareCreateResult> => {
          httpRequest.destroy();
          if (response.responseCode !== 200) {
            return Promise.reject<ShareCreateResult>(new Error(`HTTP ${response.responseCode}`));
          }
          const rawText = String(response.result ?? '');
          if (!rawText.trim()) {
            return Promise.reject<ShareCreateResult>(new Error('返回内容为空'));
          }
          return Promise.resolve()
            .then((): ShareCreateResponseLike => JSON.parse(rawText) as ShareCreateResponseLike)
            .then(
              (parsed: ShareCreateResponseLike): ShareCreateResult => {
                const id = String(parsed?.id ?? '').trim();
                if (!id) throw new Error('缺少 id');
                const urlText = String(parsed?.url ?? '').trim();
                const deep = String(parsed?.deepLink ?? '').trim() || `refhm://share/${id}`;
                return { id, url: urlText || deep, deepLink: deep };
              },
              (e: Error | string): Promise<ShareCreateResult> =>
                Promise.reject<ShareCreateResult>(new Error(`解析 JSON 失败：${String(e)}`)),
            );
        },
        (e: Error | string): Promise<ShareCreateResult> => {
          httpRequest.destroy();
          return Promise.reject<ShareCreateResult>(new Error(String(e)));
        },
      );
  }

  async fetchShareData(shareId: string, apiUrlOrOriginOverride?: string): Promise<string> {
    const url = this.getUrl(shareId, apiUrlOrOriginOverride);
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
        (response: http.HttpResponse): Promise<string> => {
          httpRequest.destroy();
          if (response.responseCode !== 200) {
            return Promise.reject<string>(new Error(`HTTP ${response.responseCode}`));
          }
          const rawText = String(response.result ?? '');
          if (!rawText.trim()) {
            return Promise.reject<string>(new Error('返回内容为空'));
          }
          return Promise.resolve()
            .then((): ShareGetResponseLike => JSON.parse(rawText) as ShareGetResponseLike)
            .then(
              (parsed: ShareGetResponseLike): string => String(parsed?.data ?? ''),
              (e: Error | string): Promise<string> => Promise.reject<string>(new Error(`解析 JSON 失败：${String(e)}`)),
            );
        },
        (e: Error | string): Promise<string> => {
          httpRequest.destroy();
          return Promise.reject<string>(new Error(String(e)));
        },
      );
  }
}

