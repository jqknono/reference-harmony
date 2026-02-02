import type { CatalogResponse } from '../models/catalog';

function joinUrl(base: string, pathname: string): string {
  const b = String(base ?? '').trim().replace(/\/+$/g, '');
  const p = String(pathname ?? '').trim().startsWith('/') ? String(pathname ?? '').trim() : `/${String(pathname ?? '').trim()}`;
  return b ? `${b}${p}` : p;
}

export type CatalogQueryLang = 'all' | 'zh' | 'en';

export function fetchCatalog(lang: CatalogQueryLang): Promise<CatalogResponse> {
  const apiBase = String(import.meta.env.VITE_API_BASE ?? '').trim();
  const useApi = !!apiBase;
  const url = useApi
    ? joinUrl(apiBase, `/api/v1/catalog?lang=${encodeURIComponent(lang)}`)
    : './catalog.json';

  return fetch(url, { method: 'GET' }).then(
    (res) => {
      if (!res.ok) {
        return res.text().then(
          (t) => Promise.reject(new Error(`HTTP ${res.status} ${res.statusText} ${t}`)),
          () => Promise.reject(new Error(`HTTP ${res.status} ${res.statusText}`)),
        );
      }
      return (res.json() as Promise<CatalogResponse>).then((data) => {
        if (useApi || lang === 'all') return data;
        return {
          ...data,
          items: (data.items ?? []).filter((it) => it?.lang === lang),
        };
      });
    },
    (e) => Promise.reject(new Error(String(e))),
  );
}

