export type UiLang = 'zh' | 'en';

export function detectUiLang(): UiLang {
  const nav = typeof navigator !== 'undefined' ? String(navigator.language ?? '') : '';
  const lower = nav.toLowerCase();
  return lower.includes('zh') ? 'zh' : 'en';
}

export function t(lang: UiLang, zh: string, en: string): string {
  return lang === 'en' ? en : zh;
}

