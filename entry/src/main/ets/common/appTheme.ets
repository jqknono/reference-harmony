export type AppThemeId = 'dark' | 'light';

export interface MarkdownThemeTokens {
  headingColor: number;
  linkColor: number;
  codeTextColor: number;
  codeBackgroundColor: number;
  tableHeaderBackgroundColor: number;
  tableCellBackgroundColor: number;
  tableBorderColor: number;
}

export interface AppThemeTokens {
  id: AppThemeId;

  pageBackgroundColor: number;
  surfaceBackgroundColor: number;
  surfaceMutedBackgroundColor: number;
  borderColor: number;
  shadowColor: number;

  titleColor: number;
  textColor: number;
  mutedTextColor: number;
  dangerTextColor: number;

  accentColor: number;
  accentTextOnColor: number;

  chipBackgroundColor: number;
  chipTextColor: number;
  chipSelectedBackgroundColor: number;
  chipSelectedTextColor: number;

  avatarBackgroundColor: number;
  avatarTextColor: number;

  qaFrontTextColor: number;
  qaBackTextColor: number;

  markdown: MarkdownThemeTokens;
}

const LIGHT_THEME: AppThemeTokens = {
  id: 'light',

  pageBackgroundColor: 0xf1f5f9,
  surfaceBackgroundColor: 0xffffff,
  surfaceMutedBackgroundColor: 0xf8fafc,
  borderColor: 0xe2e8f0,
  shadowColor: 0x14000000,

  titleColor: 0x334155,
  textColor: 0x475569,
  mutedTextColor: 0x64748b,
  dangerTextColor: 0xdc2626,

  accentColor: 0x6366f1,
  accentTextOnColor: 0xffffff,

  chipBackgroundColor: 0xe0e7ff,
  chipTextColor: 0x4338ca,
  chipSelectedBackgroundColor: 0x6366f1,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0xe0e7ff,
  avatarTextColor: 0x6366f1,

  qaFrontTextColor: 0x334155,
  qaBackTextColor: 0x475569,

  markdown: {
    headingColor: 0x334155,
    linkColor: 0x6366f1,
    codeTextColor: 0xb45309,
    codeBackgroundColor: 0xfef3c7,
    tableHeaderBackgroundColor: 0xf1f5f9,
    tableCellBackgroundColor: 0xffffff,
    tableBorderColor: 0xe2e8f0,
  },
};

const DARK_THEME: AppThemeTokens = {
  id: 'dark',

  pageBackgroundColor: 0x0d1117,
  surfaceBackgroundColor: 0x161b22,
  surfaceMutedBackgroundColor: 0x21262d,
  borderColor: 0x30363d,
  shadowColor: 0x40000000,

  titleColor: 0xf0f6fc,
  textColor: 0xe6edf3,
  mutedTextColor: 0x8b949e,
  dangerTextColor: 0xf85149,

  accentColor: 0x58a6ff,
  accentTextOnColor: 0x0d1117,

  chipBackgroundColor: 0x21262d,
  chipTextColor: 0xe6edf3,
  chipSelectedBackgroundColor: 0x238636,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0x21262d,
  avatarTextColor: 0x8b949e,

  qaFrontTextColor: 0xf0f6fc,
  qaBackTextColor: 0xe6edf3,

  markdown: {
    headingColor: 0xf0f6fc,
    linkColor: 0x58a6ff,
    codeTextColor: 0x7ee787,
    codeBackgroundColor: 0x161b22,
    tableHeaderBackgroundColor: 0x21262d,
    tableCellBackgroundColor: 0x0d1117,
    tableBorderColor: 0x30363d,
  },
};

export function getAppThemeTokens(themeId: AppThemeId): AppThemeTokens {
  if (themeId === 'dark') return DARK_THEME;
  return LIGHT_THEME;
}
