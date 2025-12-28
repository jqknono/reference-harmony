export const LAUNCH_ACTION_OPEN_RECENT_DOCS: string = 'openRecentDocs';
export const RECENT_DOC_MAX_COUNT: number = 3;

// 特性开关（默认关闭）
export const ENABLE_RECENT_DOCS: boolean = false;
export const ENABLE_ORIENTATION_MODE_SETTING: boolean = false;
// 目录清单：是否保留“收藏/最近”在原位置（完整清单）中的入口；默认不保留（避免重复入口）
export const KEEP_FAVORITE_AND_RECENT_ENTRY_IN_FULL_CATALOG_LIST: boolean = false;

export const SHOW_IMPORT_MARKDOWN_URL_SETTING: boolean = false;

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


