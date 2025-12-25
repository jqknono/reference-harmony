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

const LIGHT_THEME: AppThemeTokens = {
  id: 'light',

  // 参考 cheatsheets.zip 风格
  pageBackgroundColor: 0xf3f4f6,       // 浅灰背景
  surfaceBackgroundColor: 0xffffff,    // 白色卡片
  surfaceMutedBackgroundColor: 0xf9fafb,
  borderColor: 0xe5e7eb,
  shadowColor: 0x18000000,

  titleColor: 0x1f2937,                // 深灰标题
  textColor: 0x374151,                 // 正文
  mutedTextColor: 0x6b7280,            // 次要文字
  dangerTextColor: 0xdc2626,

  accentColor: 0x10b981,               // 绿色强调 (cheatsheets.zip 风格)
  accentTextOnColor: 0xffffff,

  chipBackgroundColor: 0xd1fae5,       // 浅绿背景
  chipTextColor: 0x047857,             // 深绿文字
  chipSelectedBackgroundColor: 0x10b981,
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0xdbeafe,     // 浅蓝背景
  avatarTextColor: 0x2563eb,           // 蓝色文字

  qaFrontTextColor: 0x1f2937,
  qaBackTextColor: 0x374151,

  sectionTitleColor: 0x059669,         // Section 标题：绿色
  cardTitleColor: 0x1e40af,            // 卡片标题：深蓝色

  markdown: {
    headingColor: 0x1f2937,
    linkColor: 0x2563eb,               // 蓝色链接
    codeTextColor: 0xc2410c,           // 橙红色代码
    codeBackgroundColor: 0xfef3c7,     // 浅黄背景
    tableHeaderBackgroundColor: 0xf3f4f6,
    tableCellBackgroundColor: 0xffffff,
    tableBorderColor: 0xe5e7eb,
  },
};

const DARK_THEME: AppThemeTokens = {
  id: 'dark',

  // 参考 wangchujiang.com/reference 风格
  pageBackgroundColor: 0x0d1117,       // 深蓝黑背景
  surfaceBackgroundColor: 0x161b22,    // 卡片背景
  surfaceMutedBackgroundColor: 0x21262d,
  borderColor: 0x30363d,
  shadowColor: 0x60000000,

  titleColor: 0xf0f6fc,                // 白色标题
  textColor: 0xc9d1d9,                 // 浅灰正文
  mutedTextColor: 0x8b949e,            // 次要文字
  dangerTextColor: 0xf85149,

  accentColor: 0x58a6ff,               // 青蓝色强调
  accentTextOnColor: 0x0d1117,

  chipBackgroundColor: 0x21262d,
  chipTextColor: 0xc9d1d9,
  chipSelectedBackgroundColor: 0x238636,  // 绿色选中
  chipSelectedTextColor: 0xffffff,

  avatarBackgroundColor: 0x3d444d,     // 更亮的背景以增加图标对比度
  avatarTextColor: 0x58a6ff,

  qaFrontTextColor: 0xf0f6fc,
  qaBackTextColor: 0xc9d1d9,

  sectionTitleColor: 0x7ee787,         // Section 标题：绿色 (参考网站)
  cardTitleColor: 0x58a6ff,            // 卡片标题：青蓝色

  markdown: {
    headingColor: 0xf0f6fc,
    linkColor: 0x58a6ff,               // 青蓝色链接
    codeTextColor: 0x7ee787,           // 绿色代码
    codeBackgroundColor: 0x0d1117,     // 深色代码背景
    tableHeaderBackgroundColor: 0x21262d,
    tableCellBackgroundColor: 0x161b22,
    tableBorderColor: 0x30363d,
  },
};

export function getAppThemeTokens(themeId: AppThemeId): AppThemeTokens {
  if (themeId === 'dark') return DARK_THEME;
  return LIGHT_THEME;
}
