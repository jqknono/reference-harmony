export type AppThemeId = 'reference' | 'coo';

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

const REFERENCE_THEME: AppThemeTokens = {
  id: 'reference',

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

const COO_THEME: AppThemeTokens = {
  id: 'coo',

  pageBackgroundColor: 0xf1f5f9,
  surfaceBackgroundColor: 0xffffff,
  surfaceMutedBackgroundColor: 0xf8fafc,
  borderColor: 0xe2e8f0,
  shadowColor: 0x14000000,

  titleColor: 0x0f172a,
  textColor: 0x334155,
  mutedTextColor: 0x64748b,
  dangerTextColor: 0xb91c1c,

  accentColor: 0x6366f1,
  accentTextOnColor: 0xffffff,

  chipBackgroundColor: 0xe2e8f0,
  chipTextColor: 0x0f172a,
  chipSelectedBackgroundColor: 0x6366f1,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0xe2e8f0,
  avatarTextColor: 0x334155,

  qaFrontTextColor: 0x334155,
  qaBackTextColor: 0x0f172a,

  markdown: {
    headingColor: 0x0f172a,
    linkColor: 0x4f46e5,
    codeTextColor: 0x334155,
    codeBackgroundColor: 0xf8fafc,
    tableHeaderBackgroundColor: 0xf8fafc,
    tableCellBackgroundColor: 0xffffff,
    tableBorderColor: 0xe2e8f0,
  },
};

export function getAppThemeTokens(themeId: AppThemeId): AppThemeTokens {
  if (themeId === 'coo') return COO_THEME;
  return REFERENCE_THEME;
}

