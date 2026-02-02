export type CatalogLang = 'zh' | 'en';

export interface CatalogItem {
  id: string;
  lang: CatalogLang;
  relPath: string;
  mdUrl: string;
  name: string;
  title: string;
  icon?: string;
  size: number;
  mtimeIso: string;
}

export interface CatalogResponse {
  version: number;
  builtAt: string;
  items: Array<CatalogItem>;
}

