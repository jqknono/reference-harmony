export type ResolvedAppThemeId = 'dark' | 'light';
export type AppThemeId = ResolvedAppThemeId | 'system';

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
  id: ResolvedAppThemeId;

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

  sectionTitleColor: number;
  cardTitleColor: number;

  markdown: MarkdownThemeTokens;
}

export function getAppThemeTokens(themeId: AppThemeId): AppThemeTokens;



