export const LAUNCH_ACTION_OPEN_RECENT_DOCS: string = 'openRecentDocs';
export const RECENT_DOC_MAX_COUNT: number = 3;

// 特性开关（默认关闭）
export const ENABLE_RECENT_DOCS: boolean = true;
export const ENABLE_ORIENTATION_MODE_SETTING: boolean = true;
// 首次启动：是否显示隐私确认弹窗（默认不显示）
export const ENABLE_PRIVACY_CONSENT_DIALOG: boolean = false;
// 目录清单：是否保留“收藏/最近”在原位置（完整清单）中的入口；默认不保留（避免重复入口）
export const KEEP_FAVORITE_AND_RECENT_ENTRY_IN_FULL_CATALOG_LIST: boolean = false;

export const SHOW_IMPORT_MARKDOWN_URL_SETTING: boolean = true;
export const TABBAR_AUTO_HIDE_EFFECTIVE_ASPECT_RATIO_THRESHOLD: number = 3;

// 调试模式（默认关闭）
// - SHOW_DEBUG_MODE_TOGGLE: 是否在“设置”里显示调试模式开关
// - 调试模式开启后：
//   - 在线清单列表加载失败时才展示错误信息（避免影响普通用户）
//   - 允许配置在线清单后端服务器地址
export const SHOW_DEBUG_MODE_TOGGLE: boolean = true;
export const DEBUG_MODE_PREF_KEY: string = 'debugModeEnabled';
export const DEBUG_SERVER_ORIGIN_PREF_KEY: string = 'debugServerOrigin';
export const DEFAULT_DEBUG_SERVER_ORIGIN: string = 'http://192.168.31.2:5179';

// 引导评价
export const ENABLE_APP_REVIEW_PROMPT: boolean = true;
export const APP_REVIEW_PREF_KEY_DO_NOT_ASK: string = 'appReviewDoNotAsk';
export const APP_REVIEW_PREF_KEY_LAUNCH_COUNT: string = 'appReviewLaunchCount';
export const APP_REVIEW_PREF_KEY_FIRST_LAUNCH_AT: string = 'appReviewFirstLaunchAt';
export const APP_REVIEW_PREF_KEY_LAST_PROMPT_AT: string = 'appReviewLastPromptAt';
export const APP_REVIEW_MIN_LAUNCH_COUNT: number = 6;
export const APP_REVIEW_MIN_DAYS_SINCE_FIRST_LAUNCH: number = 2;
export const APP_REVIEW_PROMPT_COOLDOWN_DAYS: number = 30;

// 隐私声明（AGC 隐私声明管理生成的页面）
export const PRIVACY_STATEMENT_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1844306128905764736';

// 首次启动隐私协议同意标记（存储在 preferences('settings')）
export const PRIVACY_CONSENT_PREF_KEY: string = 'privacyConsentAccepted';

/**
 * 清单黑名单：黑名单内的清单不在“目录”展示入口中出现（包含搜索/收藏/最近等入口）。
 *
 * 说明：
 * - 这里仅影响“目录”页的入口展示，不影响文档数据本身的读取（仍可被内部链接打开）。
 */
export const CATALOG_DOC_ID_BLACKLIST: ReadonlySet<string> = new Set<string>([
  'colors-named',
]);
