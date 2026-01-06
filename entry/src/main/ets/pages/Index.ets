import preferences from '@ohos.data.preferences';
import pasteboard from '@ohos.pasteboard';
import picker from '@ohos.file.picker';
import { window, font } from '@kit.ArkUI';
import webview from '@ohos.web.webview';
import bundleManager from '@ohos.bundle.bundleManager';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeTokens } from '../common/appTheme';
import type { QuizQuestion, QuizAnswer, QuizSession, QuizRecord } from '../common/quizModels';
import { generateQuizSessionId } from '../common/quizModels';
import { extractQuestionsFromDoc, selectRandomQuestions, calculateScore } from '../common/quizUtils';
import { QuizRepository } from '../common/quizRepository';
import { OnlineMdRepository } from '../common/onlineMdRepository';
import { LocalMdRepository } from '../common/localMdRepository';
import type { OnlineMdLink } from '../common/onlineMdModels';
import { peekLaunchParams, takeLaunchParams } from '../common/launchParamsStore';
import type { LaunchParams } from '../common/launchParamsStore';
import { requestAppReview } from '../common/appReview';

import type { SectionWithCards } from './index/types';
import { APP_REVIEW_MIN_DAYS_SINCE_FIRST_LAUNCH, APP_REVIEW_MIN_LAUNCH_COUNT, APP_REVIEW_PREF_KEY_DO_NOT_ASK, APP_REVIEW_PREF_KEY_FIRST_LAUNCH_AT, APP_REVIEW_PREF_KEY_LAST_PROMPT_AT, APP_REVIEW_PREF_KEY_LAUNCH_COUNT, APP_REVIEW_PROMPT_COOLDOWN_DAYS, CATALOG_DOC_ID_BLACKLIST, ENABLE_APP_REVIEW_PROMPT, ENABLE_ORIENTATION_MODE_SETTING, ENABLE_PRIVACY_CONSENT_DIALOG, ENABLE_RECENT_DOCS, LAUNCH_ACTION_OPEN_RECENT_DOCS, PRIVACY_CONSENT_PREF_KEY, PRIVACY_STATEMENT_URL, RECENT_DOC_MAX_COUNT, TABBAR_AUTO_HIDE_EFFECTIVE_ASPECT_RATIO_THRESHOLD } from './index/constants';
import { lengthToNumber, normalizeSearchTokens, cardMatchesTokens, toHexColorString } from './index/utils';
import { DocListTab } from './index/DocListTab';
import { ReadTab } from './index/ReadTab';
import { QuizTab } from './index/QuizTab';
import { SettingsTab } from './index/SettingsTab';
import { TocPanel } from './index/TocPanel';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;
type ThemePreference = 'light' |'dark' |  'system';
type ResolvedAppThemeId = 'light' | 'dark';

interface TerminableContext {
  terminateSelf?: () => Promise<void>;
}

interface BundleInfoLike {
  bundleName?: string;
  name?: string;
}

const FONT_AWESOME_SOLID_FAMILY: string = 'FontAwesomeSolid';

@Entry
@Component
struct Index {
  @State private currentTabIndex: number = 0;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  @State private lang: ReferenceLang = 'zh';
  @State private themeId: ThemePreference = 'system';
  @State private theme: AppThemeTokens = getAppThemeTokens('light');
  private systemThemeTimer: number = -1;

  @State private docs: Array<ReferenceDocSummary> = [];
  @State private zhDocCount: number = -1;
  @State private enDocCount: number = -1;
  @State private selectedDoc: ReferenceDoc | undefined = undefined;
  @State private selectedDocId: string = '';
  @State private selectedDocIcon: string = '';
  @State private selectedDocAvatarVersion: number = 0;
  @State private sectionCards: Array<SectionWithCards> = [];
  @State private searchQuery: string = '';
  @State private searchSectionCards: Array<SectionWithCards> = [];
  @State private searchResultCount: number = 0;
  @State private iconErrorKeys: Array<string> = [];
  @State private catalogSearchQuery: string = '';
  @State private catalogSearchResults: Array<ReferenceDocSummary> = [];
  @State private showTocPanel: boolean = false;
  @State private showPrivacyStatement: boolean = false;
  @State private showAbout: boolean = false;
  @State private showAppReviewPrompt: boolean = false;
  @State private showPrivacyConsentDialog: boolean = false;
  @State private showPrivacyConsentStatement: boolean = false;
  @State private searchNavSectionIndex: number = 0;
  @State private pendingTocScrollGroupIndex: number = -1;
  @State private pendingTocScrollItemIndex: number = -1;
  @State private catalogListScrollIndex: number = 0;
  @State private catalogSearchListScrollIndex: number = 0;
  @State private readTabListScrollIndex: number = 0;
  @State private readTabListSearchScrollIndex: number = 0;
  @State private readTabListScrollItemIndexInGroup: number = 0;
  @State private readTabListSearchScrollItemIndexInGroup: number = 0;
  @State private quizHistoryListScrollIndex: number = 0;
  @State private quizAnsweringScrollY: number = 0;
  @State private quizResultListScrollIndex: number = 0;
  @State private settingsScrollY: number = 0;
  @State private tocListScrollIndex: number = 0;

  private tabsController: TabsController = new TabsController();
  private catalogListScroller: ListScroller = new ListScroller();
  private listScroller: ListScroller = new ListScroller();
  private listSearchScroller: ListScroller = new ListScroller();
  private listSectionNavScroller: Scroller = new Scroller();
  private listCardNavScroller: Scroller = new Scroller();
  private quizHistoryListScroller: ListScroller = new ListScroller();
  private quizResultListScroller: ListScroller = new ListScroller();
  private quizAnsweringScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private tocListScroller: ListScroller = new ListScroller();
  private catalogSearchInputController: TextInputController = new TextInputController();
  private docSearchInputController: TextInputController = new TextInputController();
  private privacyConsentStatementController: webview.WebviewController = new webview.WebviewController();
  private repository: ReferenceRepository | undefined = undefined;
  private openDocRequestId: number = 0;
  private rootWidth: number = 0;
  private rootHeight: number = 0;
  private fontAwesomeRegistered: boolean = false;
  @State private fontSize: number = 15;
  @State private titleAreaHeight: number = 0;
  @State private bottomTabBarHeight: number = 0;
  @State private orientationMode: 'portrait' | 'landscape' | 'auto' = 'auto';
  @State private isLandscape: boolean = false;
  @State private landscapeTabBarVisible: boolean = false;
  @State private landscapeTabBarPinned: boolean = false;
  @State private learningModeEnabled: boolean = false;

  // 测验相关状态
  @State private quizMode: 'idle' | 'selecting' | 'answering' | 'result' = 'idle';
  @State private quizQuestions: Array<QuizQuestion> = [];
  @State private quizCurrentIndex: number = 0;
  @State private quizAnswers: Array<QuizAnswer> = [];
  @State private quizSelectedOptionIndex: number = -1;
  @State private quizShowAnswer: boolean = false;
  @State private quizStartTime: number = 0;
  @State private quizQuestionStartTime: number = 0;
  @State private quizRecord: QuizRecord | null = null;
  @State private quizAvailableCount: number = 0;
  private quizRepository: QuizRepository = new QuizRepository();

  // 在线 MD 相关状态
  @State private onlineMdLinks: Array<OnlineMdLink> = [];
  @State private onlineMdInputUrl: string = '';
  @State private onlineMdParsing: boolean = false;
  @State private onlineMdUpdatingLinkId: string = '';
  @State private onlineMdParseResult: string = '';
  @State private onlineMdDocs: Array<ReferenceDocSummary> = [];
  @State private onlineMdCopySuccess: boolean = false;
  private onlineMdRepository: OnlineMdRepository = new OnlineMdRepository();
  private onlineMdDocCache: Map<string, ReferenceDoc> = new Map<string, ReferenceDoc>();
  private onlineMdCopyTimer: number = -1;

  // 本地 MD 相关状态
  @State private localMdLinks: Array<OnlineMdLink> = [];
  @State private localMdImporting: boolean = false;
  @State private localMdImportResult: string = '';
  @State private localMdDocs: Array<ReferenceDocSummary> = [];
  @State private localMdCopySuccess: boolean = false;
  private localMdRepository: LocalMdRepository = new LocalMdRepository();
  private localMdDocCache: Map<string, ReferenceDoc> = new Map<string, ReferenceDoc>();
  private localMdCopyTimer: number = -1;

  // 收藏与最近阅读
  @State private favoriteDocIds: Array<string> = [];
  @State private recentDocIds: Array<string> = [];
  private recentDocAutoOpenFixApplied: boolean = false;

  private stopAllTextInputEditing(): void {
    this.catalogSearchInputController.stopEditing();
    this.docSearchInputController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
  }

  private resetReadTabScrollState(): void {
    this.readTabListScrollIndex = 0;
    this.readTabListSearchScrollIndex = 0;
    this.readTabListScrollItemIndexInGroup = 0;
    this.readTabListSearchScrollItemIndexInGroup = 0;
  }

  private resetTocScrollState(): void {
    this.tocListScrollIndex = 0;
  }

  private async consumeNotificationLaunchIfAny(): Promise<void> {
    const params: LaunchParams | undefined = takeLaunchParams();
    if (!params) return;
    const action: string = params.launchAction;
    if (action !== LAUNCH_ACTION_OPEN_RECENT_DOCS) return;

    const docId: string = params.recentDocId.trim();
    if (docId.length > 0) {
      if (this.isOnlineDoc(docId)) {
        await this.openOnlineDoc(docId);
      } else if (this.isLocalDoc(docId)) {
        await this.openLocalDoc(docId);
      } else {
        await this.openDoc(docId, true);
      }
      return;
    }

    this.switchToTab(0);
  }

  private landscapeSideMargin(): number {
    return this.isLandscape ? this.fontSize * 1.5 : 0;
  }

  private effectiveDisplayHeightExcludingTitleAndTab(rootHeight: number): number {
    const titleHeight: number = Math.max(0, this.titleAreaHeight);
    const tabHeight: number = Math.max(0, this.bottomTabBarHeight);
    return Math.max(1, rootHeight - titleHeight - tabHeight);
  }

  private setTitleAreaHeight(height: number): void {
    const next: number = Math.max(0, Math.floor(height));
    if (this.titleAreaHeight === next) return;
    this.titleAreaHeight = next;
    this.updateLandscapeFromSize(this.rootWidth, this.rootHeight);
  }

  private setBottomTabBarHeight(height: number): void {
    const next: number = Math.max(0, Math.floor(height));
    if (this.bottomTabBarHeight === next) return;
    this.bottomTabBarHeight = next;
    this.updateLandscapeFromSize(this.rootWidth, this.rootHeight);
  }

  private updateLandscapeFromArea(area: Area): void {
    const width: number = lengthToNumber(area.width);
    const height: number = lengthToNumber(area.height);
    this.rootWidth = width;
    this.rootHeight = height;
    this.updateLandscapeFromSize(width, height);
  }

  private updateLandscapeFromSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) return;
    const nextLandscape: boolean = height > 0 && width > height;
    const nextPinned: boolean = nextLandscape ? this.resolveLandscapeTabBarPinned(width, height) : false;

    const wasLandscape: boolean = this.isLandscape;
    const wasPinned: boolean = this.landscapeTabBarPinned;

    if (this.isLandscape !== nextLandscape) {
      this.isLandscape = nextLandscape;
    }
    if (this.landscapeTabBarPinned !== nextPinned) {
      this.landscapeTabBarPinned = nextPinned;
    }

    if (!nextLandscape) {
      if (this.landscapeTabBarVisible) this.landscapeTabBarVisible = false;
      if (this.landscapeTabBarPinned) this.landscapeTabBarPinned = false;
      return;
    }

    if (nextPinned) {
      if (!this.landscapeTabBarVisible) this.landscapeTabBarVisible = true;
      return;
    }

    // Wide main-content area: default to hidden (user can reveal by scrolling down).
    if ((!wasLandscape || wasPinned) && this.landscapeTabBarVisible) {
      this.landscapeTabBarVisible = false;
    }
  }

  private resolveLandscapeTabBarPinned(rootWidth: number, rootHeight: number): boolean {
    const sideMargin: number = this.fontSize * 1.5;
    const contentWidth: number = Math.max(1, rootWidth - sideMargin * 2);
    const effectiveHeight: number = this.effectiveDisplayHeightExcludingTitleAndTab(rootHeight);
    const ratio: number = contentWidth / effectiveHeight;
    return ratio <= TABBAR_AUTO_HIDE_EFFECTIVE_ASPECT_RATIO_THRESHOLD;
  }

  private setLandscapeTabBarVisible(visible: boolean): void {
    if (!this.isLandscape) return;
    if (this.landscapeTabBarPinned) {
      if (!this.landscapeTabBarVisible) this.landscapeTabBarVisible = true;
      return;
    }
    if (this.landscapeTabBarVisible === visible) return;
    const uiContext = this.getUIContext?.();
    if (uiContext && typeof uiContext.animateTo === 'function') {
      uiContext.animateTo(
        { duration: this.tabAnimationDuration(), curve: Curve.EaseInOut },
        () => {
          this.landscapeTabBarVisible = visible;
        }
      );
      return;
    }
    this.landscapeTabBarVisible = visible;
  }

  private handleLandscapeContentScroll(direction: 'up' | 'down'): void {
    if (!this.isLandscape) return;
    if (this.landscapeTabBarPinned) return;
    if (direction === 'down') {
      this.setLandscapeTabBarVisible(true);
      return;
    }
    this.setLandscapeTabBarVisible(false);
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private switchToTab(index: number): void {
    if (this.currentTabIndex === index) return;
    // 竖屏：交给 Tabs 自身动画；横屏：自定义动画更新内容。
    if (!this.isLandscape) {
      this.tabsController.changeIndex(index);
      return;
    }

    const uiContext = this.getUIContext?.();
    if (uiContext && typeof uiContext.animateTo === 'function') {
      uiContext.animateTo(
        { duration: this.tabAnimationDuration(), curve: Curve.EaseInOut },
        () => {
          this.currentTabIndex = index;
        }
      );
      return;
    }

    this.currentTabIndex = index;
  }

  private resolveSystemTheme(): ResolvedAppThemeId {
    const host = this.getUIContext().getHostContext();
    const colorMode: number | string | undefined = (host && typeof host.resourceManager?.getConfigurationSync === 'function')
      ? host.resourceManager.getConfigurationSync()?.colorMode
      : undefined;
    const colorModeNumber: number = typeof colorMode === 'number' ? colorMode : -1;
    const colorModeText: string = typeof colorMode === 'string' ? colorMode : '';
    if (colorModeNumber === 1 || colorModeText === 'light' || colorModeText === 'COLOR_MODE_LIGHT') {
      return 'light';
    }
    if (colorModeNumber === 0 || colorModeText === 'dark' || colorModeText === 'COLOR_MODE_DARK') {
      return 'dark';
    }
    return this.theme.id;
  }

  private resolveThemePreference(preferred: ThemePreference, systemMode?: ResolvedAppThemeId): ResolvedAppThemeId {
    if (preferred === 'system') {
      return systemMode ?? this.resolveSystemTheme();
    }
    return preferred;
  }

  private applyThemePreference(preferred: ThemePreference): void {
    const systemMode: ResolvedAppThemeId = this.resolveSystemTheme();
    const resolved: ResolvedAppThemeId = this.resolveThemePreference(preferred, systemMode);
    this.themeId = preferred;
    this.theme = getAppThemeTokens(resolved);
    this.applySystemBarStyle();
    if (preferred === 'system') {
      this.startSystemThemeWatcher();
    } else {
      this.stopSystemThemeWatcher();
    }
  }

  private startSystemThemeWatcher(): void {
    if (this.systemThemeTimer >= 0) return;
    this.systemThemeTimer = setInterval((): void => {
      if (this.themeId !== 'system') {
        this.stopSystemThemeWatcher();
        return;
      }
      const resolved: ResolvedAppThemeId = this.resolveSystemTheme();
      if (this.theme.id !== resolved) {
        this.theme = getAppThemeTokens(resolved);
        this.applySystemBarStyle();
      }
    }, 1500);
  }

  private stopSystemThemeWatcher(): void {
    if (this.systemThemeTimer >= 0) {
      clearInterval(this.systemThemeTimer);
      this.systemThemeTimer = -1;
    }
  }

  private async loadThemeSetting(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.applyThemePreference('system');
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('theme', 'system'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'system',
      );
    const savedText: string = (saved ?? '').trim().toLowerCase();
    const normalizedTheme: ThemePreference = (savedText === 'light' || savedText === 'reference' || savedText === 'coo')
      ? 'light'
      : (savedText === 'dark' ? 'dark' : 'system');
    this.applyThemePreference(normalizedTheme);
    if (savedText !== normalizedTheme) {
      await this.saveThemeSetting(normalizedTheme);
    }
  }

  private applySystemBarStyle(): void {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const statusBarBackground: string = toHexColorString(this.theme.pageBackgroundColor);
    const statusBarContent: string = toHexColorString(this.theme.id === 'dark' ? 0xffffff : 0x000000);
    const navigationBarBackground: string = toHexColorString(this.theme.surfaceBackgroundColor);
    const navigationBarContent: string = toHexColorString(this.theme.id === 'dark' ? 0xffffff : 0x000000);
    Promise.resolve()
      .then((): Promise<window.Window> => window.getLastWindow(host))
      .then((w: window.Window): Promise<void> => w.setWindowSystemBarProperties({
        statusBarColor: statusBarBackground,
        statusBarContentColor: statusBarContent,
        navigationBarColor: navigationBarBackground,
        navigationBarContentColor: navigationBarContent,
      }))
      .then((): void => undefined, (): void => undefined);
  }

  private async saveThemeSetting(next: ThemePreference): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('theme', next))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private async loadLangSetting(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.lang = 'zh';
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('lang', 'zh'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'zh',
      );
    this.lang = saved === 'en' ? 'en' : 'zh';
  }

  private async saveLangSetting(next: ReferenceLang): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('lang', next))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private async loadOrientationModeSetting(): Promise<void> {
    if (!ENABLE_ORIENTATION_MODE_SETTING) {
      this.orientationMode = 'portrait';
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.orientationMode = 'auto';
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('orientationMode', 'auto'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'auto',
      );
    if (saved === 'landscape' || saved === 'auto') {
      this.orientationMode = saved;
    } else {
      this.orientationMode = 'portrait';
    }
  }

  private async saveOrientationModeSetting(next: 'portrait' | 'landscape' | 'auto'): Promise<void> {
    if (!ENABLE_ORIENTATION_MODE_SETTING) return;
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('orientationMode', next))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private applyOrientationModeSetting(mode: 'portrait' | 'landscape' | 'auto'): void {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const resolvedMode: 'portrait' | 'landscape' | 'auto' = ENABLE_ORIENTATION_MODE_SETTING ? mode : 'portrait';
    let orientation: window.Orientation;
    if (resolvedMode === 'landscape') {
      orientation = window.Orientation.LANDSCAPE;
    } else if (resolvedMode === 'auto') {
      orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
    } else {
      orientation = window.Orientation.PORTRAIT;
    }
    Promise.resolve()
      .then((): Promise<window.Window> => window.getLastWindow(host))
      .then((w: window.Window): Promise<void> => w.setPreferredOrientation(orientation))
      .then((): void => undefined, (): void => undefined);
  }

  private async switchOrientationMode(next: 'portrait' | 'landscape' | 'auto'): Promise<void> {
    if (!ENABLE_ORIENTATION_MODE_SETTING) {
      if (this.orientationMode !== 'portrait') {
        this.orientationMode = 'portrait';
      }
      return;
    }
    if (this.orientationMode === next) return;
    this.orientationMode = next;
    this.applyOrientationModeSetting(next);
    await this.saveOrientationModeSetting(next);
  }

  private async loadLearningModeSetting(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.learningModeEnabled = false;
      return;
    }
    const saved: boolean = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('learningMode', false))
      .then(
        (value: ValueType): boolean => value === true || value === 'true',
        (): boolean => false,
      );
    this.learningModeEnabled = saved;
  }

  private async saveLearningModeSetting(enabled: boolean): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('learningMode', enabled))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private async toggleLearningMode(enabled: boolean): Promise<void> {
    if (this.learningModeEnabled === enabled) return;
    this.learningModeEnabled = enabled;
    await this.saveLearningModeSetting(enabled);
  }

  private async loadPrivacyConsentSetting(): Promise<void> {
    if (!ENABLE_PRIVACY_CONSENT_DIALOG) {
      this.showPrivacyConsentDialog = false;
      this.showPrivacyConsentStatement = false;
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.showPrivacyConsentDialog = true;
      return;
    }
    const accepted: boolean = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(PRIVACY_CONSENT_PREF_KEY, false))
      .then(
        (v: ValueType): boolean => v === true || v === 'true',
        (): boolean => false,
      );
    this.showPrivacyConsentDialog = !accepted;
  }

  private async savePrivacyConsentSetting(accepted: boolean): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put(PRIVACY_CONSENT_PREF_KEY, accepted))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private agreePrivacyConsent(): void {
    if (!this.showPrivacyConsentDialog) return;
    this.showPrivacyConsentDialog = false;
    this.showPrivacyConsentStatement = false;
    this.savePrivacyConsentSetting(true);
  }

  private declinePrivacyConsent(): void {
    // 不同意：保持弹窗不消失；用户可通过系统返回手势退出应用
    // 点击“取消”应直接退出应用（与常见合规弹窗行为一致）
    const host: Context | undefined = this.getUIContext().getHostContext();
    const ctx: TerminableContext | undefined = host as TerminableContext | undefined;
    if (!ctx || typeof ctx.terminateSelf !== 'function') return;
    Promise.resolve()
      .then((): Promise<void> | void => ctx.terminateSelf?.())
      .then((): void => undefined, (): void => undefined);
  }

  private async loadFavoriteAndRecentDocs(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;

    const favoriteStr: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('favoriteDocIds', '[]'))
      .then((v: ValueType): string => typeof v === 'string' ? v : '[]', (): string => '[]');

    const parsedFavorites: Array<string> = JSON.parse(favoriteStr) as Array<string>;
    this.favoriteDocIds = parsedFavorites;

    if (!ENABLE_RECENT_DOCS) {
      this.recentDocIds = [];
      this.recentDocAutoOpenFixApplied = true;
      return;
    }

    const recentStr: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('recentDocIds', '[]'))
      .then((v: ValueType): string => typeof v === 'string' ? v : '[]', (): string => '[]');
    const fixApplied: boolean = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('recentDocAutoOpenFixApplied', false))
      .then(
        (v: ValueType): boolean => v === true || v === 'true',
        (): boolean => false,
      );

    const parsedRecent: Array<string> = JSON.parse(recentStr) as Array<string>;
    this.recentDocIds = parsedRecent;
    this.recentDocAutoOpenFixApplied = fixApplied;
  }

  private async saveFavoriteDocIds(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('favoriteDocIds', JSON.stringify(this.favoriteDocIds)))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private async saveRecentDocIds(): Promise<void> {
    if (!ENABLE_RECENT_DOCS) return;
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('recentDocIds', JSON.stringify(this.recentDocIds)))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private async saveRecentDocAutoOpenFixApplied(applied: boolean): Promise<void> {
    if (!ENABLE_RECENT_DOCS) return;
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('recentDocAutoOpenFixApplied', applied))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  /**
   * 迁移旧版本 bug：
   * - 旧逻辑会在启动时“自动预加载首个文档”并错误写入 recentDocIds，
   *   导致目录第一项永远显示“最近”。
   * - 这里做一次性清理：仅在 recent 只包含首篇时清空。
   */
  private async migrateRecentDocsAutoOpenBugIfNeeded(): Promise<void> {
    if (!ENABLE_RECENT_DOCS) return;
    if (this.recentDocAutoOpenFixApplied) return;
    const firstDocId = (this.docs.length > 0 ? this.docs[0]?.id : '') ?? '';
    const shouldClear: boolean = !!firstDocId && this.recentDocIds.length === 1 && this.recentDocIds[0] === firstDocId;
    if (shouldClear) {
      this.recentDocIds = [];
      await this.saveRecentDocIds();
    }
    this.recentDocAutoOpenFixApplied = true;
    await this.saveRecentDocAutoOpenFixApplied(true);
  }

  private async toggleDocFavorite(docId: string): Promise<void> {
    const index = this.favoriteDocIds.indexOf(docId);
    if (index >= 0) {
      const next = this.favoriteDocIds.slice();
      next.splice(index, 1);
      this.favoriteDocIds = next;
    } else {
      this.favoriteDocIds = [docId, ...this.favoriteDocIds];
    }
    await this.saveFavoriteDocIds();
  }

  private async addToRecentDocs(docId: string): Promise<void> {
    if (!ENABLE_RECENT_DOCS) return;
    const next = this.recentDocIds.filter((id: string): boolean => id !== docId);
    next.unshift(docId);
    if (next.length > RECENT_DOC_MAX_COUNT) {
      next.splice(RECENT_DOC_MAX_COUNT);
    }
    this.recentDocIds = next;
    await this.saveRecentDocIds();
  }

  private async ensureRepository(): Promise<ReferenceRepository | undefined> {
    if (this.repository) {
      return this.repository;
    }
    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.errorText = this.t('无法获取 HostContext', 'Failed to get HostContext');
      return undefined;
    }
    this.repository = new ReferenceRepository(host.resourceManager);
    return this.repository;
  }

  private rebuildSectionCards(doc: ReferenceDoc): void {
    const bySection: Map<string, Array<ReferenceCardData>> = new Map<string, Array<ReferenceCardData>>();
    for (let i = 0; i < doc.cards.length; i++) {
      const card: ReferenceCardData = doc.cards[i];
      if (card.sectionId === 'intro') continue;
      let list: Array<ReferenceCardData> | undefined = bySection.get(card.sectionId);
      if (!list) {
        list = new Array<ReferenceCardData>();
        bySection.set(card.sectionId, list);
      }
      list.push(card);
    }

    let sections: Array<ReferenceSection> = doc.sections.filter(
      (s: ReferenceSection): boolean => s.id !== 'intro'
    );
    if (sections.length === 0) {
      const defaultSection: ReferenceSection = { id: 'default', title: this.t('内容', 'Content'), startIndex: 0 };
      sections = [defaultSection];
    }

    const groups: Array<SectionWithCards> = new Array<SectionWithCards>();
    for (let i = 0; i < sections.length; i++) {
      const section: ReferenceSection = sections[i];
      const cards: Array<ReferenceCardData> = bySection.get(section.id) ?? new Array<ReferenceCardData>();
      const group: SectionWithCards = { section: section, cards: cards };
      groups.push(group);
    }
    this.sectionCards = groups;
  }

  private rebuildSearchResults(): void {
    const doc = this.selectedDoc;
    const tokens = normalizeSearchTokens(this.searchQuery);
    if (!doc || tokens.length === 0) {
      this.searchSectionCards = [];
      this.searchResultCount = 0;
      return;
    }

    const bySection: Map<string, Array<ReferenceCardData>> = new Map<string, Array<ReferenceCardData>>();
    let matchedCount = 0;

    for (let i = 0; i < doc.cards.length; i++) {
      const card = doc.cards[i];
      if (card.sectionId === 'intro') continue;
      if (!cardMatchesTokens(card, tokens)) continue;
      matchedCount++;
      let list = bySection.get(card.sectionId);
      if (!list) {
        list = new Array<ReferenceCardData>();
        bySection.set(card.sectionId, list);
      }
      list.push(card);
    }

    let sections: Array<ReferenceSection> = doc.sections.filter(
      (s: ReferenceSection): boolean => s.id !== 'intro'
    );
    if (sections.length === 0) {
      const defaultSection: ReferenceSection = { id: 'default', title: this.t('内容', 'Content'), startIndex: 0 };
      sections = [defaultSection];
    }

    const groups: Array<SectionWithCards> = new Array<SectionWithCards>();
    const knownSectionIds: Set<string> = new Set<string>();
    for (let i = 0; i < sections.length; i++) {
      const section: ReferenceSection = sections[i];
      knownSectionIds.add(section.id);
      const cards: Array<ReferenceCardData> = bySection.get(section.id) ?? new Array<ReferenceCardData>();
      if (cards.length === 0) continue;
      groups.push({ section, cards });
    }

    const extraSectionIds: Array<string> = [];
    bySection.forEach((_cards: Array<ReferenceCardData>, sectionId: string): void => {
      if (!knownSectionIds.has(sectionId)) extraSectionIds.push(sectionId);
    });
    extraSectionIds.sort();

    for (let i = 0; i < extraSectionIds.length; i++) {
      const sectionId = extraSectionIds[i];
      const cards = bySection.get(sectionId) ?? new Array<ReferenceCardData>();
      if (cards.length === 0) continue;
      groups.push({ section: { id: sectionId, title: sectionId, startIndex: 0 }, cards });
    }

    this.searchSectionCards = groups;
    this.searchResultCount = matchedCount;
    this.searchNavSectionIndex = 0;
  }

  private rebuildCatalogSearchResults(): void {
    const query = this.catalogSearchQuery.trim().toLowerCase();
    if (!query) {
      this.catalogSearchResults = [];
      return;
    }

    const results: Array<ReferenceDocSummary> = [];
    const pushIfMatched = (doc: ReferenceDocSummary): void => {
      const haystack = [doc.name ?? '', doc.title ?? '', doc.id].join(' ').toLowerCase();
      if (haystack.indexOf(query) >= 0) {
        results.push(doc);
      }
    };

    for (let i = 0; i < this.docs.length; i++) {
      pushIfMatched(this.docs[i]);
    }
    for (let i = 0; i < this.onlineMdDocs.length; i++) {
      pushIfMatched(this.onlineMdDocs[i]);
    }
    for (let i = 0; i < this.localMdDocs.length; i++) {
      pushIfMatched(this.localMdDocs[i]);
    }

    results.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => {
      const ak = (a.name || a.title || a.id || '').trim().toLowerCase();
      const bk = (b.name || b.title || b.id || '').trim().toLowerCase();
      if (ak < bk) return -1;
      if (ak > bk) return 1;
      return 0;
    });
    this.catalogSearchResults = results;
  }

  private async openDoc(docId: string, switchToReadTab: boolean = true, recordRecent: boolean = true): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    const repo = await this.ensureRepository();
    if (!repo) {
      return;
    }

    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';
    await repo.getDocByLang(this.lang, docId).then(
      (doc: ReferenceDoc): void => {
        if (requestId !== this.openDocRequestId) return;
        if (!doc.icon) {
          const summary = this.docs.find((d: ReferenceDocSummary): boolean => d.id === docId);
          if (summary?.icon) {
            doc.icon = summary.icon;
          }
        }
        this.selectedDocIcon = doc.icon ?? '';
        this.selectedDoc = doc;
        this.selectedDocId = docId;
        this.selectedDocAvatarVersion = requestId;
        this.rebuildSectionCards(doc);
        this.rebuildSearchResults();
        this.updateQuizAvailableCount();
        if (recordRecent) {
          this.addToRecentDocs(docId);
        }
        this.resetReadTabScrollState();
        this.resetTocScrollState();
        this.listScroller.scrollToIndex(0);
        this.listSearchScroller.scrollToIndex(0);
        if (switchToReadTab) {
          this.switchToTab(1);
        }
      },
      (e: Error | string): void => {
        if (requestId !== this.openDocRequestId) return;
        this.errorText = this.t(`加载文档失败：${String(e)}`, `Failed to load doc: ${String(e)}`);
      },
    );
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private async openDocAndQuiz(docId: string): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    const repo = await this.ensureRepository();
    if (!repo) {
      return;
    }

    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';
    await repo.getDocByLang(this.lang, docId).then(
      (doc: ReferenceDoc): void => {
        if (requestId !== this.openDocRequestId) return;
        if (!doc.icon) {
          const summary = this.docs.find((d: ReferenceDocSummary): boolean => d.id === docId);
          if (summary?.icon) {
            doc.icon = summary.icon;
          }
        }
        this.selectedDocIcon = doc.icon ?? '';
        this.selectedDoc = doc;
        this.selectedDocId = docId;
        this.selectedDocAvatarVersion = requestId;
        this.rebuildSectionCards(doc);
        this.rebuildSearchResults();
        this.updateQuizAvailableCount();
        this.addToRecentDocs(docId);
        this.resetReadTabScrollState();
        this.resetTocScrollState();
        this.listScroller.scrollToIndex(0);
        this.listSearchScroller.scrollToIndex(0);
        this.switchToTab(2);
      },
      (e: Error | string): void => {
        if (requestId !== this.openDocRequestId) return;
        this.errorText = this.t(`加载文档失败：${String(e)}`, `Failed to load doc: ${String(e)}`);
      },
    );
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private async switchLang(next: ReferenceLang): Promise<void> {
    if (this.lang === next) return;
    this.stopAllTextInputEditing();
    this.lang = next;
    // 先清空与文档/目录相关的状态，避免语言已切换但目录仍短暂显示旧清单。
    this.docs = [];
    this.selectedDoc = undefined;
    this.selectedDocId = '';
    this.selectedDocIcon = '';
    this.sectionCards = [];
    this.searchQuery = '';
    this.searchSectionCards = [];
    this.searchResultCount = 0;
    this.catalogSearchQuery = '';
    this.catalogSearchResults = [];
    this.catalogListScrollIndex = 0;
    this.catalogSearchListScrollIndex = 0;
    this.quizHistoryListScrollIndex = 0;
    this.quizAnsweringScrollY = 0;
    this.quizResultListScrollIndex = 0;
    this.settingsScrollY = 0;
    this.resetReadTabScrollState();
    this.resetTocScrollState();
    this.iconErrorKeys = [];
    this.errorText = '';
    this.showTocPanel = false;

    // 保存设置不应阻塞目录清单切换
    this.saveLangSetting(next);
    await this.loadManifest(true);
    await this.loadManifestCounts();
  }

  private async switchTheme(next: ThemePreference): Promise<void> {
    if (this.themeId === next) return;
    this.applyThemePreference(next);
    await this.saveThemeSetting(next);
  }

  private async loadManifest(autoOpenFirst: boolean = true): Promise<void> {
    const repo = await this.ensureRepository();
    if (!repo) {
      return;
    }

    const targetLang: ReferenceLang = this.lang;

    this.loading = true;
    this.errorText = '';
    await repo.getManifestByLang(targetLang).then(
      async (manifest: ReferenceManifest): Promise<void> => {
        if (this.lang !== targetLang) {
          return;
        }
        this.docs = (manifest.docs ?? [])
          .filter((doc: ReferenceDocSummary): boolean => !CATALOG_DOC_ID_BLACKLIST.has(doc.id))
          .map((doc: ReferenceDocSummary): ReferenceDocSummary => ({
            id: doc.id,
            name: doc.name || doc.title || doc.id,
            title: doc.title || doc.name || doc.id,
            icon: doc.icon,
            file: doc.file,
            sectionCount: doc.sectionCount,
            cardCount: doc.cardCount,
          }));
        this.rebuildCatalogSearchResults();
        await this.migrateRecentDocsAutoOpenBugIfNeeded();
        if (autoOpenFirst && !this.selectedDocId && this.docs.length > 0) {
          await this.openDoc(this.docs[0].id, false, false);
        }
      },
      (e: Error | string): void => {
        if (this.lang !== targetLang) {
          return;
        }
        this.errorText = this.t(
          `加载 manifest 失败：${String(e)}\n\n请先运行 tools/sync_reference_docs.mjs 生成 rawfile 数据。`,
          `Failed to load manifest: ${String(e)}\n\nRun tools/sync_reference_docs.mjs to generate rawfile data.`,
        );
      },
    );
    if (this.lang === targetLang) {
      this.loading = false;
    }
  }

  private async loadManifestCounts(): Promise<void> {
    const repo = await this.ensureRepository();
    if (!repo) return;

    const zh = repo.getManifestByLang('zh').then(
      (manifest: ReferenceManifest): number =>
        (manifest.docs ?? []).filter((doc: ReferenceDocSummary): boolean => !CATALOG_DOC_ID_BLACKLIST.has(doc.id)).length,
      (): number => -1,
    );
    const en = repo.getManifestByLang('en').then(
      (manifest: ReferenceManifest): number =>
        (manifest.docs ?? []).filter((doc: ReferenceDocSummary): boolean => !CATALOG_DOC_ID_BLACKLIST.has(doc.id)).length,
      (): number => -1,
    );

    await Promise.all([zh, en]).then(
      (counts: Array<number>): void => {
        this.zhDocCount = counts.length > 0 ? counts[0] : -1;
        this.enDocCount = counts.length > 1 ? counts[1] : -1;
      },
      (): void => {
        this.zhDocCount = -1;
        this.enDocCount = -1;
      },
    );
  }

  aboutToDisappear(): void {
    this.stopSystemThemeWatcher();
  }

  async aboutToAppear(): Promise<void> {
    this.ensureFontAwesomeRegistered();

    const launchParams: LaunchParams | undefined = peekLaunchParams();
    const launchAction: string = launchParams?.launchAction ?? '';
    const skipAutoOpenFirst: boolean = launchAction === LAUNCH_ACTION_OPEN_RECENT_DOCS;

    await this.loadThemeSetting();
    await this.loadLangSetting();
    await this.loadPrivacyConsentSetting();
    await this.loadOrientationModeSetting();
    await this.loadLearningModeSetting();
    await this.loadFavoriteAndRecentDocs();
    await this.loadManifest(!skipAutoOpenFirst);
    await this.loadManifestCounts();
    await this.loadQuizRecord();
    await this.loadOnlineMdLinks();
    await this.loadLocalMdLinks();
    await this.consumeNotificationLaunchIfAny();
    await this.recordLaunchAndMaybePromptForReview();
  }

  private async loadAppReviewPrefs(): Promise<Preferences | undefined> {
    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;
    try {
      return await preferences.getPreferences(host, 'settings');
    } catch (_) {
      return undefined;
    }
  }

  private async getSelfBundleName(): Promise<string> {
    try {
      const info = (await bundleManager.getBundleInfoForSelf(0)) as BundleInfoLike;
      const bundleName: string = typeof info?.bundleName === 'string' ? info.bundleName.trim() : '';
      if (bundleName) return bundleName;
      const name: string = typeof info?.name === 'string' ? info.name.trim() : '';
      return name;
    } catch (_) {
      return '';
    }
  }

  private async setAppReviewDoNotAsk(doNotAsk: boolean): Promise<void> {
    const prefs = await this.loadAppReviewPrefs();
    if (!prefs) return;
    try {
      await prefs.put(APP_REVIEW_PREF_KEY_DO_NOT_ASK, doNotAsk);
      await prefs.flush();
    } catch (_) {
      // ignore
    }
  }

  private async requestAppReviewFromUserAction(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    const bundleName: string = await this.getSelfBundleName();
    const result = await requestAppReview(host, bundleName);
    if (result !== 'failed') {
      await this.setAppReviewDoNotAsk(true);
    }
  }

  private async recordLaunchAndMaybePromptForReview(): Promise<void> {
    if (!ENABLE_APP_REVIEW_PROMPT) return;
    if (this.showPrivacyConsentDialog) return;

    const prefs = await this.loadAppReviewPrefs();
    if (!prefs) return;

    const now: number = Date.now();
    const toNumber = (value: ValueType, fallback: number): number => {
      if (typeof value === 'number') return value;
      if (typeof value === 'string') {
        const n = Number(value);
        return Number.isFinite(n) ? n : fallback;
      }
      if (typeof value === 'boolean') return value ? 1 : 0;
      return fallback;
    };
    const toBool = (value: ValueType, fallback: boolean): boolean => {
      if (typeof value === 'boolean') return value;
      if (typeof value === 'number') return value !== 0;
      if (typeof value === 'string') return value === 'true' || value === '1';
      return fallback;
    };

    const doNotAsk: boolean = toBool(await prefs.get(APP_REVIEW_PREF_KEY_DO_NOT_ASK, false), false);
    if (doNotAsk) return;

    let firstLaunchAt: number = toNumber(await prefs.get(APP_REVIEW_PREF_KEY_FIRST_LAUNCH_AT, 0), 0);
    if (firstLaunchAt <= 0) {
      firstLaunchAt = now;
      try {
        await prefs.put(APP_REVIEW_PREF_KEY_FIRST_LAUNCH_AT, firstLaunchAt);
      } catch (_) {
        // ignore
      }
    }

    let launchCount: number = toNumber(await prefs.get(APP_REVIEW_PREF_KEY_LAUNCH_COUNT, 0), 0);
    launchCount = Math.max(0, launchCount) + 1;
    try {
      await prefs.put(APP_REVIEW_PREF_KEY_LAUNCH_COUNT, launchCount);
    } catch (_) {
      // ignore
    }

    const lastPromptAt: number = toNumber(await prefs.get(APP_REVIEW_PREF_KEY_LAST_PROMPT_AT, 0), 0);
    const cooldownMs: number = APP_REVIEW_PROMPT_COOLDOWN_DAYS * 24 * 60 * 60 * 1000;
    if (lastPromptAt > 0 && now - lastPromptAt < cooldownMs) {
      try {
        await prefs.flush();
      } catch (_) {
        // ignore
      }
      return;
    }

    const minDaysMs: number = APP_REVIEW_MIN_DAYS_SINCE_FIRST_LAUNCH * 24 * 60 * 60 * 1000;
    const eligible: boolean = launchCount >= APP_REVIEW_MIN_LAUNCH_COUNT && now - firstLaunchAt >= minDaysMs;
    if (!eligible) {
      try {
        await prefs.flush();
      } catch (_) {
        // ignore
      }
      return;
    }

    try {
      await prefs.put(APP_REVIEW_PREF_KEY_LAST_PROMPT_AT, now);
      await prefs.flush();
    } catch (_) {
      // ignore
    }

    this.showAppReviewPrompt = true;
  }

  private async loadQuizRecord(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    this.quizRecord = await this.quizRepository.getQuizRecord(host);
  }

  private async loadOnlineMdLinks(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const stored = await this.onlineMdRepository.getLinks(host);
    this.onlineMdLinks = stored;
    await this.rebuildOnlineMdDocs();
  }

  private async loadLocalMdLinks(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const stored = await this.localMdRepository.getLinks(host);
    this.localMdLinks = stored;
    await this.rebuildLocalMdDocs();
  }

  private findOnlineMdLink(linkId: string): OnlineMdLink | undefined {
    for (let i = 0; i < this.onlineMdLinks.length; i++) {
      const link = this.onlineMdLinks[i];
      if (link?.id === linkId) return link;
    }
    return undefined;
  }

  private async ensureOnlineMdDocReady(linkId: string): Promise<ReferenceDoc | undefined> {
    const inMemory = this.onlineMdDocCache.get(linkId);
    if (inMemory) return inMemory;

    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;

    const cachedDoc = await this.onlineMdRepository.getDocFromCache(host, linkId);
    if (cachedDoc) {
      this.onlineMdDocCache.set(linkId, cachedDoc);
      return cachedDoc;
    }

    const link = this.findOnlineMdLink(linkId);
    const url = (link?.url ?? '').trim();
    if (!url) return undefined;

    const result = await this.onlineMdRepository.fetchAndParse(url);
    const doc = result.doc;
    if (!result.success || !doc) {
      this.errorText = this.t(
        `加载在线文档失败：${result.error ?? ''}`,
        `Failed to load online doc: ${result.error ?? ''}`
      );
      return undefined;
    }

    await this.onlineMdRepository.saveDocToCache(host, linkId, doc);
    this.onlineMdDocCache.set(linkId, doc);
    await this.rebuildOnlineMdDocs();
    return doc;
  }

  private async rebuildOnlineMdDocs(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    const summaries: Array<ReferenceDocSummary> = [];
    for (let i = 0; i < this.onlineMdLinks.length; i++) {
      const link = this.onlineMdLinks[i];
      const linkId = link?.id ?? '';
      if (!linkId) continue;

      const cachedDoc = await this.onlineMdRepository.getDocFromCache(host, linkId);
      if (cachedDoc) {
        this.onlineMdDocCache.set(linkId, cachedDoc);
        summaries.push({
          id: linkId,
          name: link.name || cachedDoc.name,
          title: cachedDoc.title,
          file: `online:${link.url}`,
          sectionCount: cachedDoc.sections.length,
          cardCount: cachedDoc.cards.length,
        });
        continue;
      }

      const fallbackName = (link?.name ?? linkId).trim() || linkId;
      summaries.push({
        id: linkId,
        name: fallbackName,
        title: '',
        file: `online:${link?.url ?? ''}`,
        sectionCount: 0,
        cardCount: 0,
      });
    }
    this.onlineMdDocs = summaries;
    this.rebuildCatalogSearchResults();
  }

  private async rebuildLocalMdDocs(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    const summaries: Array<ReferenceDocSummary> = [];
    for (let i = 0; i < this.localMdLinks.length; i++) {
      const link = this.localMdLinks[i];
      const linkId = link?.id ?? '';
      if (!linkId) continue;

      const cachedDoc = await this.localMdRepository.getDocFromCache(host, linkId);
      if (cachedDoc) {
        this.localMdDocCache.set(linkId, cachedDoc);
        summaries.push({
          id: linkId,
          name: link.name || cachedDoc.name,
          title: cachedDoc.title,
          file: `local:${link.url}`,
          sectionCount: cachedDoc.sections.length,
          cardCount: cachedDoc.cards.length,
        });
        continue;
      }

      const fallbackName = (link?.name ?? linkId).trim() || linkId;
      summaries.push({
        id: linkId,
        name: fallbackName,
        title: '',
        file: `local:${link?.url ?? ''}`,
        sectionCount: 0,
        cardCount: 0,
      });
    }
    this.localMdDocs = summaries;
    this.rebuildCatalogSearchResults();
  }

  private async parseAndAddOnlineMd(): Promise<void> {
    const url = this.onlineMdInputUrl.trim();
    if (!url) {
      this.onlineMdParseResult = this.t('请输入 URL', 'Please enter a URL');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.onlineMdParseResult = this.t('URL 必须以 http:// 或 https:// 开头', 'URL must start with http:// or https://');
      return;
    }

    if (!OnlineMdRepository.isMarkdownUrl(url)) {
      this.onlineMdParseResult = this.t(
        `仅支持 Markdown 文件：URL 必须以 .md/.markdown 结尾（当前：${url}）`,
        `Only Markdown files are supported: URL must end with .md/.markdown (current: ${url})`
      );
      return;
    }

    this.onlineMdParsing = true;
    this.onlineMdParseResult = '';

    const result = await this.onlineMdRepository.fetchAndParse(url);

    if (!result.success) {
      this.onlineMdParsing = false;
      this.onlineMdParseResult = this.t(`解析失败：${result.error}`, `Parse failed: ${result.error}`);
      return;
    }

    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.onlineMdParsing = false;
      this.onlineMdParseResult = this.t('无法获取上下文', 'Failed to get context');
      return;
    }

    const doc = result.doc;
    if (!doc) {
      this.onlineMdParsing = false;
      this.onlineMdParseResult = this.t('解析结果为空', 'Parse result is empty');
      return;
    }

    const newLink = await this.onlineMdRepository.addLink(host, url, doc.name);
    await this.onlineMdRepository.saveDocToCache(host, newLink.id, doc);
    this.onlineMdDocCache.set(newLink.id, doc);

    const stored = await this.onlineMdRepository.getLinks(host);
    this.onlineMdLinks = stored;
    await this.rebuildOnlineMdDocs();

    this.onlineMdParsing = false;
    this.onlineMdInputUrl = '';
    this.onlineMdParseResult = this.t(
      `解析成功：${doc.name}（${doc.sections.length} 章节，${doc.cards.length} 卡片）`,
      `Parse success: ${doc.name} (${doc.sections.length} sections, ${doc.cards.length} cards)`
    );
  }

  private async updateOnlineMd(linkId: string): Promise<void> {
    if (!linkId.trim()) return;
    if (this.onlineMdUpdatingLinkId) return;

    const host = this.getUIContext().getHostContext();
    if (!host) return;

    const link = this.findOnlineMdLink(linkId);
    const url = (link?.url ?? '').trim();
    if (!url) return;

    this.onlineMdUpdatingLinkId = linkId;
    this.onlineMdParseResult = '';
    try {
      const result = await this.onlineMdRepository.fetchAndParse(url);
      const doc = result.doc;
      if (!result.success || !doc) {
        this.onlineMdParseResult = this.t(`更新失败:${result.error ?? ''}`, `Update failed: ${result.error ?? ''}`);
        return;
      }

      await this.onlineMdRepository.saveDocToCache(host, linkId, doc);
      this.onlineMdDocCache.set(linkId, doc);
      await this.rebuildOnlineMdDocs();

      if (this.selectedDocId === linkId) {
        this.selectedDoc = doc;
        this.rebuildSectionCards(doc);
        this.rebuildSearchResults();
        this.updateQuizAvailableCount();
      }

      this.onlineMdParseResult = this.t(
        `更新成功:${doc.name}（${doc.sections.length} 节，${doc.cards.length} 卡）`,
        `Updated: ${doc.name} (${doc.sections.length} sections, ${doc.cards.length} cards)`
      );
    } finally {
      this.onlineMdUpdatingLinkId = '';
    }
  }

  private async removeOnlineMd(linkId: string): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    await this.onlineMdRepository.removeLink(host, linkId);
    await this.onlineMdRepository.deleteDocCache(host, linkId);
    this.onlineMdDocCache.delete(linkId);

    const stored = await this.onlineMdRepository.getLinks(host);
    this.onlineMdLinks = stored;
    await this.rebuildOnlineMdDocs();
  }

  private copyOnlineMdUrl(url: string): void {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    Promise.resolve()
      .then((): Promise<void> => systemPasteboard.setData(pasteboardData))
      .then((): void => {
        if (this.onlineMdCopyTimer !== -1) {
          clearTimeout(this.onlineMdCopyTimer);
        }
        this.onlineMdCopySuccess = true;
        this.onlineMdCopyTimer = setTimeout(() => {
          this.onlineMdCopySuccess = false;
          this.onlineMdCopyTimer = -1;
        }, 3000);
      }, (): void => undefined);
  }

  private copyLocalMdUri(uri: string): void {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, uri);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    Promise.resolve()
      .then((): Promise<void> => systemPasteboard.setData(pasteboardData))
      .then((): void => {
        if (this.localMdCopyTimer !== -1) {
          clearTimeout(this.localMdCopyTimer);
        }
        this.localMdCopySuccess = true;
        this.localMdCopyTimer = setTimeout(() => {
          this.localMdCopySuccess = false;
          this.localMdCopyTimer = -1;
        }, 3000);
      }, (): void => undefined);
  }

  private async removeLocalMd(linkId: string): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    await this.localMdRepository.removeLink(host, linkId);
    await this.localMdRepository.deleteDocCache(host, linkId);
    this.localMdDocCache.delete(linkId);

    const stored = await this.localMdRepository.getLinks(host);
    this.localMdLinks = stored;
    await this.rebuildLocalMdDocs();
  }

  private async selectLocalMarkdownFileUri(): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.md', '.markdown'];

    return new picker.DocumentViewPicker()
      .select(options)
      .then(
        (uris: Array<string>): string => (uris && uris.length > 0 ? String(uris[0] ?? '') : ''),
        (): string => '',
      );
  }

  private async importLocalMarkdown(): Promise<void> {
    if (this.localMdImporting) return;
    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.localMdImportResult = this.t('无法获取上下文', 'Failed to get context');
      return;
    }

    this.stopAllTextInputEditing();
    this.localMdImporting = true;
    this.localMdImportResult = '';

    try {
      const uri = (await this.selectLocalMarkdownFileUri()).trim();
      if (!uri) {
        return;
      }

      const result = await this.localMdRepository.readAndParse(uri);
      const doc = result.doc;
      if (!result.success || !doc) {
        this.localMdImportResult = this.t(`导入失败：${result.error ?? ''}`, `Import failed: ${result.error ?? ''}`);
        return;
      }

      for (let i = 0; i < this.localMdLinks.length; i++) {
        const link = this.localMdLinks[i];
        if ((link?.url ?? '').trim() !== uri) continue;
        await this.localMdRepository.saveDocToCache(host, link.id, doc);
        this.localMdDocCache.set(link.id, doc);
        await this.rebuildLocalMdDocs();
        this.localMdImportResult = this.t(
          `已更新：${doc.name}（${doc.sections.length} 章节，${doc.cards.length} 卡片）`,
          `Updated: ${doc.name} (${doc.sections.length} sections, ${doc.cards.length} cards)`
        );
        return;
      }

      const newLink = await this.localMdRepository.addLink(host, uri, doc.name || this.t('本地 Markdown', 'Local Markdown'));
      await this.localMdRepository.saveDocToCache(host, newLink.id, doc);
      this.localMdDocCache.set(newLink.id, doc);

      const stored = await this.localMdRepository.getLinks(host);
      this.localMdLinks = stored;
      await this.rebuildLocalMdDocs();

      this.localMdImportResult = this.t(
        `导入成功：${doc.name}（${doc.sections.length} 章节，${doc.cards.length} 卡片）`,
        `Import success: ${doc.name} (${doc.sections.length} sections, ${doc.cards.length} cards)`
      );
    } finally {
      this.localMdImporting = false;
    }
  }

  private isOnlineDoc(docId: string): boolean {
    return docId.startsWith('online_');
  }

  private isLocalDoc(docId: string): boolean {
    return docId.startsWith('local_');
  }

  private async openOnlineDoc(linkId: string): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';

    const doc = await this.ensureOnlineMdDocReady(linkId);
    if (requestId !== this.openDocRequestId) return;
    if (!doc) {
      this.loading = false;
      return;
    }
    this.selectedDoc = doc;

    this.selectedDocId = linkId;
    this.selectedDocAvatarVersion = requestId;
    this.rebuildSectionCards(doc);
    this.rebuildSearchResults();
    this.updateQuizAvailableCount();
    this.addToRecentDocs(linkId);
    this.resetReadTabScrollState();
    this.resetTocScrollState();
    this.switchToTab(1);
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private async openOnlineDocAndQuiz(linkId: string): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';

    const doc = await this.ensureOnlineMdDocReady(linkId);
    if (requestId !== this.openDocRequestId) return;
    if (!doc) {
      this.loading = false;
      return;
    }
    this.selectedDoc = doc;

    this.selectedDocId = linkId;
    this.selectedDocAvatarVersion = requestId;
    this.rebuildSectionCards(doc);
    this.rebuildSearchResults();
    this.updateQuizAvailableCount();
    this.addToRecentDocs(linkId);
    this.resetReadTabScrollState();
    this.resetTocScrollState();
    this.switchToTab(2);
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private findLocalMdLink(linkId: string): OnlineMdLink | undefined {
    for (let i = 0; i < this.localMdLinks.length; i++) {
      const link = this.localMdLinks[i];
      if (link?.id === linkId) return link;
    }
    return undefined;
  }

  private async ensureLocalMdDocReady(linkId: string): Promise<ReferenceDoc | undefined> {
    const inMemory = this.localMdDocCache.get(linkId);
    if (inMemory) return inMemory;

    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;

    const cachedDoc = await this.localMdRepository.getDocFromCache(host, linkId);
    if (cachedDoc) {
      this.localMdDocCache.set(linkId, cachedDoc);
      return cachedDoc;
    }

    const link = this.findLocalMdLink(linkId);
    const uri = (link?.url ?? '').trim();
    if (!uri) return undefined;

    const result = await this.localMdRepository.readAndParse(uri);
    const doc = result.doc;
    if (!result.success || !doc) {
      this.errorText = this.t(
        `加载本地文档失败：${result.error ?? ''}`,
        `Failed to load local doc: ${result.error ?? ''}`
      );
      return undefined;
    }

    await this.localMdRepository.saveDocToCache(host, linkId, doc);
    this.localMdDocCache.set(linkId, doc);
    await this.rebuildLocalMdDocs();
    return doc;
  }

  private async openLocalDoc(linkId: string): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';

    const doc = await this.ensureLocalMdDocReady(linkId);
    if (requestId !== this.openDocRequestId) return;
    if (!doc) {
      this.loading = false;
      return;
    }
    this.selectedDoc = doc;
    this.selectedDocId = linkId;
    this.selectedDocAvatarVersion = requestId;
    this.rebuildSectionCards(doc);
    this.rebuildSearchResults();
    this.updateQuizAvailableCount();
    this.addToRecentDocs(linkId);
    this.resetReadTabScrollState();
    this.resetTocScrollState();
    this.switchToTab(1);
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private async openLocalDocAndQuiz(linkId: string): Promise<void> {
    this.openDocRequestId++;
    const requestId = this.openDocRequestId;
    this.loading = true;
    this.errorText = '';
    this.selectedDocIcon = '';

    const doc = await this.ensureLocalMdDocReady(linkId);
    if (requestId !== this.openDocRequestId) return;
    if (!doc) {
      this.loading = false;
      return;
    }
    this.selectedDoc = doc;
    this.selectedDocId = linkId;
    this.selectedDocAvatarVersion = requestId;
    this.rebuildSectionCards(doc);
    this.rebuildSearchResults();
    this.updateQuizAvailableCount();
    this.addToRecentDocs(linkId);
    this.resetReadTabScrollState();
    this.resetTocScrollState();
    this.switchToTab(2);
    if (requestId === this.openDocRequestId) {
      this.loading = false;
    }
  }

  private updateQuizAvailableCount(): void {
    if (!this.selectedDoc) {
      this.quizAvailableCount = 0;
      return;
    }
    const questions = extractQuestionsFromDoc(this.selectedDoc, this.lang);
    this.quizAvailableCount = questions.length;
  }

  private async startQuiz(questionCount: number): Promise<void> {
    if (!this.selectedDoc) return;

    const allQuestions = extractQuestionsFromDoc(this.selectedDoc, this.lang);
    if (allQuestions.length === 0) return;

    const selected = selectRandomQuestions(allQuestions, questionCount);
    this.quizQuestions = selected;
    this.quizCurrentIndex = 0;
    this.quizAnswers = [];
    this.quizSelectedOptionIndex = -1;
    this.quizShowAnswer = false;
    this.quizStartTime = Date.now();
    this.quizQuestionStartTime = Date.now();
    this.quizAnsweringScrollY = 0;
    this.quizResultListScrollIndex = 0;
    this.quizMode = 'answering';
  }

  private selectQuizOption(index: number): void {
    if (this.quizShowAnswer) return;
    this.quizSelectedOptionIndex = index;
  }

  private confirmQuizAnswer(): void {
    if (this.quizSelectedOptionIndex < 0) return;
    if (this.quizShowAnswer) return;

    const question = this.quizQuestions[this.quizCurrentIndex];
    const isCorrect = this.quizSelectedOptionIndex === question.correctIndex;
    const answerTime = Date.now() - this.quizQuestionStartTime;

    const answer: QuizAnswer = {
      questionId: question.id,
      selectedIndex: this.quizSelectedOptionIndex,
      isCorrect,
      answerTime,
    };
    this.quizAnswers.push(answer);
    this.quizShowAnswer = true;
  }

  private nextQuizQuestion(): void {
    if (this.quizCurrentIndex + 1 >= this.quizQuestions.length) {
      this.finishQuiz();
      return;
    }

    this.quizCurrentIndex += 1;
    this.quizSelectedOptionIndex = -1;
    this.quizShowAnswer = false;
    this.quizQuestionStartTime = Date.now();
    this.quizAnsweringScrollY = 0;
    this.quizAnsweringScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
  }

  private async finishQuiz(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host || !this.selectedDoc) {
      this.quizMode = 'idle';
      return;
    }

    let correctCount = 0;
    for (let i = 0; i < this.quizAnswers.length; i++) {
      if (this.quizAnswers[i].isCorrect) {
        correctCount += 1;
      }
    }

    const session: QuizSession = {
      id: generateQuizSessionId(),
      docId: this.selectedDoc.id,
      docName: this.selectedDoc.name,
      docTitle: this.selectedDoc.title || this.selectedDoc.name,
      startTime: this.quizStartTime,
      endTime: Date.now(),
      questions: this.quizQuestions,
      answers: this.quizAnswers,
      score: calculateScore(correctCount, this.quizQuestions.length),
      correctCount,
      totalCount: this.quizQuestions.length,
    };

    this.quizRecord = await this.quizRepository.addQuizSession(host, session);
    this.quizResultListScrollIndex = 0;
    this.quizMode = 'result';
  }

  private resetQuiz(): void {
    this.quizMode = 'idle';
    this.quizQuestions = [];
    this.quizCurrentIndex = 0;
    this.quizAnswers = [];
    this.quizSelectedOptionIndex = -1;
    this.quizShowAnswer = false;
    this.quizAnsweringScrollY = 0;
    this.quizResultListScrollIndex = 0;
  }

  onBackPress(): boolean {
    if (this.showAppReviewPrompt) {
      this.showAppReviewPrompt = false;
      return true;
    }
    if (this.showPrivacyConsentDialog) {
      if (this.showPrivacyConsentStatement) {
        this.showPrivacyConsentStatement = false;
        return true;
      }
      // 交给系统处理返回手势以退出应用
      return false;
    }
    if (this.showTocPanel) {
      this.stopAllTextInputEditing();
      this.showTocPanel = false;
      return true;
    }
    if (this.currentTabIndex === 3) {
      if (this.showPrivacyStatement) {
        this.showPrivacyStatement = false;
        return true;
      }
      if (this.showAbout) {
        this.showAbout = false;
        return true;
      }
    }
    if (this.currentTabIndex !== 0) {
      this.switchToTab(0);
      return true;
    }
    // 目录页允许系统处理返回手势以退出应用
    return false;
  }

  private getTabLabel(index: number): string {
    if (index === 0) return this.t('目录', 'Catalog');
    // 英文 "Cheatsheet" 在窄屏/大字号下易被截断；插入零宽空格以允许必要时在单词内部换行。
    if (index === 1) return this.t('清单', 'Cheat\u200Bsheet');
    if (index === 2) return this.t('测验', 'Quiz');
    return this.t('设置', 'Settings');
  }

  private ensureFontAwesomeRegistered(): void {
    if (this.fontAwesomeRegistered) return;
    this.fontAwesomeRegistered = true;
    try {
      font.registerFont({
        familyName: FONT_AWESOME_SOLID_FAMILY,
        familySrc: $rawfile('fonts/fa-solid-900.ttf'),
      });
    } catch (_) {
      // ignore
    }
  }

  private getTabIconText(index: number): string {
    // Font Awesome Free (Solid) unicode values.
    if (index === 0) return '\uF03A'; // list
    if (index === 1) return '\uF02D'; // book
    if (index === 2) return '\uF059'; // question-circle
    return '\uF013'; // gear
  }

  private tabIconSize(): number {
    return this.isLandscape ? this.fontSize * 1.1 : this.fontSize * 1.2;
  }

  private tabLabelFontSize(): number {
    return this.isLandscape ? this.fontSize * 0.95 : this.fontSize * 0.75;
  }

  private tabItemVerticalPadding(): number {
    return this.isLandscape ? this.fontSize * 0.35 : this.fontSize * 0.45;
  }

  private tabIconLabelGap(): number {
    return this.isLandscape ? this.fontSize * 0.55 : this.fontSize * 0.25;
  }

  private tabAnimationDuration(): number {
    return 260;
  }

  @Builder
  private PrivacyConsentButtons(): void {
    Row({ space: this.fontSize * 0.8 }) {
      Text(this.t('取消', 'Cancel'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(this.fontSize * 0.95)
        .fontColor(this.theme.mutedTextColor)
        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.55, bottom: this.fontSize * 0.55 })
        .backgroundColor(this.theme.chipBackgroundColor)
        .borderRadius(this.fontSize * 0.75)
        .onClick(() => this.declinePrivacyConsent());

      Text(this.t('同意', 'Agree'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(this.fontSize * 0.95)
        .fontColor(this.theme.chipSelectedTextColor)
        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.55, bottom: this.fontSize * 0.55 })
        .backgroundColor(this.theme.chipSelectedBackgroundColor)
        .borderRadius(this.fontSize * 0.75)
        .onClick(() => this.agreePrivacyConsent());
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private PrivacyConsentOverlay(): void {
    if (this.showPrivacyConsentStatement) {
      Column({ space: 0 }) {
        Row() {
          Text(this.t('业务与隐私的声明', 'Business & Privacy Statement'))
            .fontSize(this.fontSize * 1.05)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleColor);
          Blank();
          Text(this.t('返回', 'Back'))
            .fontSize(this.fontSize * 0.95)
            .fontColor(this.theme.accentColor)
            .onClick(() => {
              this.showPrivacyConsentStatement = false;
            });
        }
        .width('100%')
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.8 });

        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Web({ src: PRIVACY_STATEMENT_URL, controller: this.privacyConsentStatementController })
          .width('100%')
          .layoutWeight(1);

        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row() {
          this.PrivacyConsentButtons();
        }
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.8, bottom: this.fontSize * 1 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.pageBackgroundColor);
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .opacity(0.35);

        Column({ space: this.fontSize * 0.8 }) {
          Text(this.t('隐私提示', 'Privacy Notice'))
            .fontSize(this.fontSize * 1.2)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleColor);

          Text(this.t(
            '在您使用本应用前，请阅读并同意《业务与隐私的声明》。在您同意前，我们不会启用可能收集个人信息的功能。',
            'Before using this app, please read and agree to the Business & Privacy Statement. We will not enable features that may collect personal data before you agree.'
          ))
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.mutedTextColor)
            .lineHeight(this.fontSize * 1.35);

          Text(this.t('《业务与隐私的声明》', 'Business & Privacy Statement'))
            .fontSize(this.fontSize * 0.95)
            .fontColor(this.theme.accentColor)
            .decoration({ type: TextDecorationType.Underline })
            .onClick(() => {
              this.showPrivacyConsentStatement = true;
            });

          this.PrivacyConsentButtons();
        }
        .width(this.isLandscape ? '70%' : '90%')
        .padding({ left: this.fontSize * 1.1, right: this.fontSize * 1.1, top: this.fontSize * 1.1, bottom: this.fontSize * 1 })
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 1)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });
      }
      .width('100%')
      .height('100%');
    }
  }

  @Builder
  private AppReviewOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .opacity(0.35);

      Column({ space: this.fontSize * 0.8 }) {
        Text(this.t('喜欢这个应用吗？', 'Enjoying the app?'))
          .fontSize(this.fontSize * 1.2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleColor);

        Text(this.t(
          '如果对你有帮助，欢迎在应用市场给个好评，支持我们持续改进。',
          'If it helps, a quick rating in the app store would mean a lot.'
        ))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.mutedTextColor)
          .lineHeight(this.fontSize * 1.35);

        Text(this.t('不再提示', "Don't ask again"))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.accentColor)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => {
            this.showAppReviewPrompt = false;
            this.setAppReviewDoNotAsk(true);
          });

        Row({ space: this.fontSize * 0.8 }) {
          Text(this.t('稍后', 'Later'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .fontSize(this.fontSize * 0.95)
            .fontColor(this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.55, bottom: this.fontSize * 0.55 })
            .backgroundColor(this.theme.chipBackgroundColor)
            .borderRadius(this.fontSize * 0.75)
            .onClick(() => {
              this.showAppReviewPrompt = false;
            });

          Text(this.t('去评价', 'Rate now'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .fontSize(this.fontSize * 0.95)
            .fontColor(this.theme.chipSelectedTextColor)
            .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.55, bottom: this.fontSize * 0.55 })
            .backgroundColor(this.theme.chipSelectedBackgroundColor)
            .borderRadius(this.fontSize * 0.75)
            .onClick(() => {
              this.showAppReviewPrompt = false;
              this.requestAppReviewFromUserAction();
            });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
      }
      .width(this.isLandscape ? '70%' : '90%')
      .padding({ left: this.fontSize * 1.1, right: this.fontSize * 1.1, top: this.fontSize * 1.1, bottom: this.fontSize * 1 })
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 1)
      .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private TabBarItem(index: number): void {
    Column() {
      if (this.isLandscape) {
      Row({ space: this.tabIconLabelGap() }) {
        Text(this.getTabIconText(index))
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.tabIconSize())
          .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor);

        Text(this.getTabLabel(index))
          .fontSize(this.tabLabelFontSize())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
          .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal);
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);
    } else {
      Column({ space: this.tabIconLabelGap() }) {
        Text(this.getTabIconText(index))
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.tabIconSize())
          .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor);

        Text(this.getTabLabel(index))
          .width('100%')
          .fontSize(this.tabLabelFontSize())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Clip })
          .textAlign(TextAlign.Center)
          .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor)
          .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal);
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center);
    }
    }
    .width('100%')
    .layoutWeight(1)
    // 让每个 Tab item 占满等宽区域，避免左右 padding 吃掉可用宽度导致标题截断
    .padding({ top: this.tabItemVerticalPadding(), bottom: this.tabItemVerticalPadding() })
    .onClick((): void => {
      if (this.currentTabIndex === index) return;
      this.stopAllTextInputEditing();
      this.switchToTab(index);
    });
  }

  @Builder
  private BottomTabBar(): void {
    Column({ space: 0 }) {
      Divider()
        .color(this.theme.borderColor)
        .strokeWidth(this.fontSize * 0.07);

      Row() {
        this.TabBarItem(0);
        this.TabBarItem(1);
        this.TabBarItem(2);
        this.TabBarItem(3);
      }
      .width('100%')
      .padding({
        left: this.fontSize * 0.5,
        right: this.fontSize * 0.5,
        top: this.fontSize * 0.5,
        bottom: this.fontSize * 0.5,
      });
    }
    .width('100%')
    .backgroundColor(this.theme.surfaceBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((_: Area, area: Area) => {
      this.setBottomTabBarHeight(lengthToNumber(area.height));
    });
  }

  @Builder
  private CurrentTabContent(): void {
    if (this.currentTabIndex === 0) {
      DocListTab({
        currentTabIndex: this.currentTabIndex,
        loading: this.loading,
        errorText: this.errorText,
        catalogSearchQuery: this.catalogSearchQuery,
        catalogSearchResults: this.catalogSearchResults,
        listScrollIndex: this.catalogListScrollIndex,
        searchListScrollIndex: this.catalogSearchListScrollIndex,
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        favoriteDocIds: this.favoriteDocIds,
        recentDocIds: this.recentDocIds,
        iconErrorKeys: this.iconErrorKeys,
        catalogSearchInputController: this.catalogSearchInputController,
        listScroller: this.catalogListScroller,
        tabsController: this.tabsController,
        docs: this.docs,
        onlineMdDocs: this.onlineMdDocs,
        localMdDocs: this.localMdDocs,
        onOpenDoc: (docId: string, switchToReadTab: boolean): void => { this.openDoc(docId, switchToReadTab); },
        onOpenOnlineDoc: (docId: string): void => { this.openOnlineDoc(docId); },
        onOpenLocalDoc: (docId: string): void => { this.openLocalDoc(docId); },
        onOpenDocAndQuiz: (docId: string): void => { this.openDocAndQuiz(docId); },
        onOpenOnlineDocAndQuiz: (docId: string): void => { this.openOnlineDocAndQuiz(docId); },
        onOpenLocalDocAndQuiz: (docId: string): void => { this.openLocalDocAndQuiz(docId); },
        onRebuildCatalogSearchResults: (): void => { this.rebuildCatalogSearchResults(); },
        onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
        onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
      });
    } else if (this.currentTabIndex === 1) {
      ReadTab({
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        learningModeEnabled: this.learningModeEnabled,
        searchQuery: this.searchQuery,
        searchSectionCards: this.searchSectionCards,
        searchResultCount: this.searchResultCount,
        searchNavSectionIndex: this.searchNavSectionIndex,
        sectionCards: this.sectionCards,
        loading: this.loading,
        errorText: this.errorText,
        iconErrorKeys: this.iconErrorKeys,
        pendingTocScrollGroupIndex: this.pendingTocScrollGroupIndex,
        pendingTocScrollItemIndex: this.pendingTocScrollItemIndex,
        selectedDoc: this.selectedDoc ?? null,
        selectedDocId: this.selectedDocId,
        selectedDocIcon: this.selectedDocIcon,
        selectedDocAvatarVersion: this.selectedDocAvatarVersion,
        favoriteDocIds: this.favoriteDocIds,
        listScrollIndex: this.readTabListScrollIndex,
        listSearchScrollIndex: this.readTabListSearchScrollIndex,
        listScrollItemIndexInGroup: this.readTabListScrollItemIndexInGroup,
        listSearchScrollItemIndexInGroup: this.readTabListSearchScrollItemIndexInGroup,
        listScroller: this.listScroller,
        listSearchScroller: this.listSearchScroller,
        listSectionNavScroller: this.listSectionNavScroller,
        listCardNavScroller: this.listCardNavScroller,
        docSearchInputController: this.docSearchInputController,
        onToggleDocFavorite: (docId: string): void => { this.toggleDocFavorite(docId); },
        onShowTocPanel: (): void => { this.stopAllTextInputEditing(); this.showTocPanel = true; },
        onRebuildSearchResults: (): void => { this.rebuildSearchResults(); },
        onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
        onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
      });
    } else if (this.currentTabIndex === 2) {
      QuizTab({
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        historyListScrollIndex: this.quizHistoryListScrollIndex,
        answeringScrollY: this.quizAnsweringScrollY,
        resultListScrollIndex: this.quizResultListScrollIndex,
        historyListScroller: this.quizHistoryListScroller,
        resultListScroller: this.quizResultListScroller,
        answeringScroller: this.quizAnsweringScroller,
        quizMode: this.quizMode,
        quizQuestions: this.quizQuestions,
        quizCurrentIndex: this.quizCurrentIndex,
        quizAnswers: this.quizAnswers,
        quizSelectedOptionIndex: this.quizSelectedOptionIndex,
        quizShowAnswer: this.quizShowAnswer,
        quizStartTime: this.quizStartTime,
        quizQuestionStartTime: this.quizQuestionStartTime,
        quizRecord: this.quizRecord,
        quizAvailableCount: this.quizAvailableCount,
        selectedDoc: this.selectedDoc ?? null,
        quizRepository: this.quizRepository,
        onStartQuiz: (count: number): void => { this.startQuiz(count); },
        onSelectQuizOption: (index: number): void => { this.selectQuizOption(index); },
        onConfirmQuizAnswer: (): void => { this.confirmQuizAnswer(); },
        onNextQuizQuestion: (): void => { this.nextQuizQuestion(); },
        onResetQuiz: (): void => { this.resetQuiz(); },
        onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
        onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
      });
    } else {
      SettingsTab({
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        scrollY: this.settingsScrollY,
        showPrivacyStatement: this.showPrivacyStatement,
        showAbout: this.showAbout,
        scroller: this.settingsScroller,
        themeId: this.themeId,
        orientationMode: this.orientationMode,
        learningModeEnabled: this.learningModeEnabled,
        zhDocCount: this.zhDocCount,
        enDocCount: this.enDocCount,
        onlineMdInputUrl: this.onlineMdInputUrl,
        onlineMdParsing: this.onlineMdParsing,
        onlineMdUpdatingLinkId: this.onlineMdUpdatingLinkId,
        onlineMdParseResult: this.onlineMdParseResult,
        onlineMdLinks: this.onlineMdLinks,
        onlineMdCopySuccess: this.onlineMdCopySuccess,
        localMdImporting: this.localMdImporting,
        localMdImportResult: this.localMdImportResult,
        localMdLinks: this.localMdLinks,
        localMdCopySuccess: this.localMdCopySuccess,
        onSwitchOrientationMode: (mode: 'portrait' | 'landscape' | 'auto'): void => { this.switchOrientationMode(mode); },
        onSwitchLang: (lang: ReferenceLang): void => { this.switchLang(lang); },
        onSwitchTheme: (theme: ThemePreference): void => { this.switchTheme(theme); },
        onToggleLearningMode: (enabled: boolean): void => { this.toggleLearningMode(enabled); },
        onParseAndAddOnlineMd: (): void => { this.parseAndAddOnlineMd(); },
        onUpdateOnlineMd: (linkId: string): void => { this.updateOnlineMd(linkId); },
        onRemoveOnlineMd: (linkId: string): void => { this.removeOnlineMd(linkId); },
        onCopyOnlineMdUrl: (url: string): void => { this.copyOnlineMdUrl(url); },
        onImportLocalMarkdown: (): void => { this.importLocalMarkdown(); },
        onRemoveLocalMd: (linkId: string): void => { this.removeLocalMd(linkId); },
        onCopyLocalMdUri: (uri: string): void => { this.copyLocalMdUri(uri); },
        onRequestAppReview: (): void => { this.requestAppReviewFromUserAction(); },
        onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
        onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
      });
    }
  }

  build() {
    Stack() {
      if (this.isLandscape) {
        Column() {
          Stack() {
            this.CurrentTabContent();
          }
          .layoutWeight(1)
          .padding({ left: this.landscapeSideMargin(), right: this.landscapeSideMargin() })
          .width('100%');

          if (this.landscapeTabBarPinned || this.landscapeTabBarVisible) {
            this.BottomTabBar();
          }
        }
        .width('100%')
        .height('100%');
      } else {
        Column() {
          Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex, controller: this.tabsController }) {
            TabContent() {
              DocListTab({
                currentTabIndex: this.currentTabIndex,
                loading: this.loading,
                errorText: this.errorText,
                catalogSearchQuery: this.catalogSearchQuery,
                catalogSearchResults: this.catalogSearchResults,
                listScrollIndex: this.catalogListScrollIndex,
                searchListScrollIndex: this.catalogSearchListScrollIndex,
                theme: this.theme,
                fontSize: this.fontSize,
                lang: this.lang,
                isLandscape: this.isLandscape,
                favoriteDocIds: this.favoriteDocIds,
                recentDocIds: this.recentDocIds,
                iconErrorKeys: this.iconErrorKeys,
                catalogSearchInputController: this.catalogSearchInputController,
                listScroller: this.catalogListScroller,
                tabsController: this.tabsController,
                docs: this.docs,
                onlineMdDocs: this.onlineMdDocs,
                localMdDocs: this.localMdDocs,
                onOpenDoc: (docId: string, switchToReadTab: boolean): void => { this.openDoc(docId, switchToReadTab); },
                onOpenOnlineDoc: (docId: string): void => { this.openOnlineDoc(docId); },
                onOpenLocalDoc: (docId: string): void => { this.openLocalDoc(docId); },
                onOpenDocAndQuiz: (docId: string): void => { this.openDocAndQuiz(docId); },
                onOpenOnlineDocAndQuiz: (docId: string): void => { this.openOnlineDocAndQuiz(docId); },
                onOpenLocalDocAndQuiz: (docId: string): void => { this.openLocalDocAndQuiz(docId); },
                onRebuildCatalogSearchResults: (): void => { this.rebuildCatalogSearchResults(); },
                onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
                onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
              });
            }
            .tabBar(this.TabBarItem(0));

            TabContent() {
              ReadTab({
                theme: this.theme,
                fontSize: this.fontSize,
                lang: this.lang,
                isLandscape: this.isLandscape,
                learningModeEnabled: this.learningModeEnabled,
                searchQuery: this.searchQuery,
                searchSectionCards: this.searchSectionCards,
                searchResultCount: this.searchResultCount,
                searchNavSectionIndex: this.searchNavSectionIndex,
                sectionCards: this.sectionCards,
                loading: this.loading,
                errorText: this.errorText,
                iconErrorKeys: this.iconErrorKeys,
                pendingTocScrollGroupIndex: this.pendingTocScrollGroupIndex,
                pendingTocScrollItemIndex: this.pendingTocScrollItemIndex,
                selectedDoc: this.selectedDoc ?? null,
                selectedDocId: this.selectedDocId,
                selectedDocIcon: this.selectedDocIcon,
                selectedDocAvatarVersion: this.selectedDocAvatarVersion,
                favoriteDocIds: this.favoriteDocIds,
                listScrollIndex: this.readTabListScrollIndex,
                listSearchScrollIndex: this.readTabListSearchScrollIndex,
                listScrollItemIndexInGroup: this.readTabListScrollItemIndexInGroup,
                listSearchScrollItemIndexInGroup: this.readTabListSearchScrollItemIndexInGroup,
                listScroller: this.listScroller,
                listSearchScroller: this.listSearchScroller,
                listSectionNavScroller: this.listSectionNavScroller,
                listCardNavScroller: this.listCardNavScroller,
                docSearchInputController: this.docSearchInputController,
                onToggleDocFavorite: (docId: string): void => { this.toggleDocFavorite(docId); },
                onShowTocPanel: (): void => { this.stopAllTextInputEditing(); this.showTocPanel = true; },
                onRebuildSearchResults: (): void => { this.rebuildSearchResults(); },
                onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
                onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
              });
            }
            .tabBar(this.TabBarItem(1));

            TabContent() {
              QuizTab({
                theme: this.theme,
                fontSize: this.fontSize,
                lang: this.lang,
                isLandscape: this.isLandscape,
                historyListScrollIndex: this.quizHistoryListScrollIndex,
                answeringScrollY: this.quizAnsweringScrollY,
                resultListScrollIndex: this.quizResultListScrollIndex,
                historyListScroller: this.quizHistoryListScroller,
                resultListScroller: this.quizResultListScroller,
                answeringScroller: this.quizAnsweringScroller,
                quizMode: this.quizMode,
                quizQuestions: this.quizQuestions,
                quizCurrentIndex: this.quizCurrentIndex,
                quizAnswers: this.quizAnswers,
                quizSelectedOptionIndex: this.quizSelectedOptionIndex,
                quizShowAnswer: this.quizShowAnswer,
                quizStartTime: this.quizStartTime,
                quizQuestionStartTime: this.quizQuestionStartTime,
                quizRecord: this.quizRecord,
                quizAvailableCount: this.quizAvailableCount,
                selectedDoc: this.selectedDoc ?? null,
                quizRepository: this.quizRepository,
                onStartQuiz: (count: number): void => { this.startQuiz(count); },
                onSelectQuizOption: (index: number): void => { this.selectQuizOption(index); },
                onConfirmQuizAnswer: (): void => { this.confirmQuizAnswer(); },
                onNextQuizQuestion: (): void => { this.nextQuizQuestion(); },
                onResetQuiz: (): void => { this.resetQuiz(); },
                onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
                onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
              });
            }
            .tabBar(this.TabBarItem(2));

            TabContent() {
              SettingsTab({
                theme: this.theme,
                fontSize: this.fontSize,
                lang: this.lang,
                isLandscape: this.isLandscape,
                scrollY: this.settingsScrollY,
                showPrivacyStatement: this.showPrivacyStatement,
                showAbout: this.showAbout,
                scroller: this.settingsScroller,
                themeId: this.themeId,
                orientationMode: this.orientationMode,
                learningModeEnabled: this.learningModeEnabled,
                zhDocCount: this.zhDocCount,
                enDocCount: this.enDocCount,
                onlineMdInputUrl: this.onlineMdInputUrl,
                onlineMdParsing: this.onlineMdParsing,
                onlineMdUpdatingLinkId: this.onlineMdUpdatingLinkId,
                onlineMdParseResult: this.onlineMdParseResult,
                onlineMdLinks: this.onlineMdLinks,
                onlineMdCopySuccess: this.onlineMdCopySuccess,
                localMdImporting: this.localMdImporting,
                localMdImportResult: this.localMdImportResult,
                localMdLinks: this.localMdLinks,
                localMdCopySuccess: this.localMdCopySuccess,
                onSwitchOrientationMode: (mode: 'portrait' | 'landscape' | 'auto'): void => { this.switchOrientationMode(mode); },
                onSwitchLang: (lang: ReferenceLang): void => { this.switchLang(lang); },
                onSwitchTheme: (theme: ThemePreference): void => { this.switchTheme(theme); },
                onToggleLearningMode: (enabled: boolean): void => { this.toggleLearningMode(enabled); },
                onParseAndAddOnlineMd: (): void => { this.parseAndAddOnlineMd(); },
                onUpdateOnlineMd: (linkId: string): void => { this.updateOnlineMd(linkId); },
                onRemoveOnlineMd: (linkId: string): void => { this.removeOnlineMd(linkId); },
                onCopyOnlineMdUrl: (url: string): void => { this.copyOnlineMdUrl(url); },
                onImportLocalMarkdown: (): void => { this.importLocalMarkdown(); },
                onRemoveLocalMd: (linkId: string): void => { this.removeLocalMd(linkId); },
                onCopyLocalMdUri: (uri: string): void => { this.copyLocalMdUri(uri); },
                onRequestAppReview: (): void => { this.requestAppReviewFromUserAction(); },
                onLandscapeScrollDirection: (direction: 'up' | 'down'): void => { this.handleLandscapeContentScroll(direction); },
                onTitleAreaHeightChange: (height: number): void => { this.setTitleAreaHeight(height); },
              });
          }
            .tabBar(this.TabBarItem(3));
          }
          .layoutWeight(1)
          .animationDuration(this.tabAnimationDuration())
          .animationCurve(Curve.EaseInOut)
          .scrollable(false)
          .barHeight(0)
          .barBackgroundColor(this.theme.surfaceBackgroundColor)
          .onChange((index: number) => {
            this.currentTabIndex = index;
          });

          this.BottomTabBar();
        }
        .width('100%')
        .height('100%');
      }

      // Measure-only instance: ensures we can get a stable bottom tab height even when the tab bar is hidden in landscape.
      if (this.bottomTabBarHeight <= 0) {
        Column() {
          Blank().layoutWeight(1);
          this.BottomTabBar();
        }
        .width('100%')
        .height('100%')
        .opacity(0)
        .enabled(false);
      }

      if (this.showTocPanel) {
        TocPanel({
          theme: this.theme,
          fontSize: this.fontSize,
          lang: this.lang,
          selectedDocId: this.selectedDocId,
          sectionCards: this.sectionCards,
          listScrollIndex: this.tocListScrollIndex,
          listScroller: this.tocListScroller,
          onClose: (): void => { this.stopAllTextInputEditing(); this.showTocPanel = false; },
          onScrollToCard: (groupIndex: number, cardIndex: number): void => {
            this.stopAllTextInputEditing();
            this.showTocPanel = false;
            const hasSearch: boolean = !!this.searchQuery.trim();
            if (hasSearch) {
              this.searchQuery = '';
              this.pendingTocScrollGroupIndex = groupIndex;
              this.pendingTocScrollItemIndex = cardIndex + 1;
            } else {
              this.listScroller.scrollToItemInGroup(groupIndex, cardIndex + 1, true, ScrollAlign.START);
            }
          },
        });
      }

      if (this.showAppReviewPrompt && !this.showPrivacyConsentDialog) {
        this.AppReviewOverlay();
      }

      if (this.showPrivacyConsentDialog) {
        this.PrivacyConsentOverlay();
      }
    }
    .backgroundColor(this.theme.pageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_: Area, area: Area) => {
      this.updateLandscapeFromArea(area);
    })
    .width('100%')
    .height('100%');
  }
}
