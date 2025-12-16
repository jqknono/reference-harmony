export type ReferenceCardKind = 'text' | 'qa' | 'code';

export interface ReferenceCardData {
  id: string;
  sectionId: string;
  title: string;
  kind: ReferenceCardKind;
  front?: string;
  back?: string;
  body?: string;
  lang?: string;
  code?: string;
}

export interface ReferenceSection {
  id: string;
  title: string;
  startIndex: number;
}

export interface ReferenceDocSummary {
  id: string;
  title: string;
  file: string; // rawfile relative path, e.g. "reference/javascript.json"
  sectionCount: number;
  cardCount: number;
}

export interface ReferenceManifestSource {
  repo: string;
  docsPath: string;
  ref: string;
  generatedAt: string;
}

export interface ReferenceDocSource {
  repo: string;
  path: string;
  ref: string;
  url: string;
  generatedAt: string;
}

export interface ReferenceManifest {
  source: ReferenceManifestSource;
  docs: Array<ReferenceDocSummary>;
}

export interface ReferenceDoc {
  id: string;
  title: string;
  sections: Array<ReferenceSection>;
  cards: Array<ReferenceCardData>;
  source: ReferenceDocSource;
}
