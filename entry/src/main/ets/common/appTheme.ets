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
  surfaceMutedBackgroundColor: 0xf6f8fa,
  borderColor: 0xd0d7de,
  shadowColor: 0x14000000,

  titleColor: 0x24292f,
  textColor: 0x24292f,
  mutedTextColor: 0x57606a,
  dangerTextColor: 0xcf222e,

  accentColor: 0x0969da,
  accentTextOnColor: 0xffffff,

  chipBackgroundColor: 0xeaeef2,
  chipTextColor: 0x24292f,
  chipSelectedBackgroundColor: 0x0969da,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0xeaeef2,
  avatarTextColor: 0x57606a,

  qaFrontTextColor: 0x24292f,
  qaBackTextColor: 0x1f2328,

  markdown: {
    headingColor: 0x24292f,
    linkColor: 0x0969da,
    codeTextColor: 0x24292f,
    codeBackgroundColor: 0xf6f8fa,
    tableHeaderBackgroundColor: 0xf6f8fa,
    tableCellBackgroundColor: 0xffffff,
    tableBorderColor: 0xd0d7de,
  },
};

const DARK_THEME: AppThemeTokens = {
  id: 'dark',

  pageBackgroundColor: 0x0b1220,
  surfaceBackgroundColor: 0x111827,
  surfaceMutedBackgroundColor: 0x0f172a,
  borderColor: 0x1f2937,
  shadowColor: 0x40000000,

  titleColor: 0xe5e7eb,
  textColor: 0xd1d5db,
  mutedTextColor: 0x9ca3af,
  dangerTextColor: 0xfca5a5,

  accentColor: 0x60a5fa,
  accentTextOnColor: 0x0b1220,

  chipBackgroundColor: 0x111827,
  chipTextColor: 0xe5e7eb,
  chipSelectedBackgroundColor: 0x2563eb,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0x111827,
  avatarTextColor: 0x9ca3af,

  qaFrontTextColor: 0xe5e7eb,
  qaBackTextColor: 0xd1d5db,

  markdown: {
    headingColor: 0xe5e7eb,
    linkColor: 0x60a5fa,
    codeTextColor: 0xe5e7eb,
    codeBackgroundColor: 0x0f172a,
    tableHeaderBackgroundColor: 0x0f172a,
    tableCellBackgroundColor: 0x111827,
    tableBorderColor: 0x1f2937,
  },
};

export function getAppThemeTokens(themeId: AppThemeId): AppThemeTokens {
  if (themeId === 'dark') return DARK_THEME;
  return LIGHT_THEME;
}
