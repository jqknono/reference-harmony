import preferences from '@ohos.data.preferences';
import pasteboard from '@ohos.pasteboard';
import picker from '@ohos.file.picker';
import { window } from '@kit.ArkUI';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeId, AppThemeTokens } from '../common/appTheme';
import type { QuizQuestion, QuizAnswer, QuizSession, QuizRecord } from '../common/quizModels';
import { generateQuizSessionId } from '../common/quizModels';
import { extractQuestionsFromDoc, selectRandomQuestions, calculateScore } from '../common/quizUtils';
import { QuizRepository } from '../common/quizRepository';
import { OnlineMdRepository } from '../common/onlineMdRepository';
import { LocalMdRepository } from '../common/localMdRepository';
import type { OnlineMdLink } from '../common/onlineMdModels';
import { peekLaunchParams, takeLaunchParams } from '../common/launchParamsStore';
import type { LaunchParams } from '../common/launchParamsStore';

import type { SectionWithCards } from './index/types';
import { DEFAULT_ONLINE_MD_LINK_ID, DEFAULT_ONLINE_MD_URL, DEFAULT_ONLINE_MD_NAME, LAUNCH_ACTION_OPEN_RECENT_DOCS, RECENT_DOC_MAX_COUNT } from './index/constants';
import { lengthToNumber, normalizeSearchTokens, cardMatchesTokens } from './index/utils';
import { DocListTab } from './index/DocListTab';
import { ReadTab } from './index/ReadTab';
import { QuizTab } from './index/QuizTab';
import { SettingsTab } from './index/SettingsTab';
import { TocPanel } from './index/TocPanel';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

@Entry
@Component
struct Index {
  @State private currentTabIndex: number = 0;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  @State private lang: ReferenceLang = 'zh';
  @State private themeId: AppThemeId = 'dark';
  @State private theme: AppThemeTokens = getAppThemeTokens('dark');

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
  @State private searchNavSectionIndex: number = 0;
  @State private pendingTocScrollGroupIndex: number = -1;
  @State private pendingTocScrollItemIndex: number = -1;

  private tabsController: TabsController = new TabsController();
  private listScroller: ListScroller = new ListScroller();
  private listSearchScroller: ListScroller = new ListScroller();
  private listSectionNavScroller: Scroller = new Scroller();
  private listCardNavScroller: Scroller = new Scroller();
  private catalogSearchInputController: TextInputController = new TextInputController();
  private docSearchInputController: TextInputController = new TextInputController();
  private repository: ReferenceRepository | undefined = undefined;
  private openDocRequestId: number = 0;
  @State private fontSize: number = 15;
  @State private orientationMode: 'portrait' | 'landscape' | 'auto' = 'portrait';
  @State private isLandscape: boolean = false;
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

  private stopAllTextInputEditing(): void {
    this.catalogSearchInputController.stopEditing();
    this.docSearchInputController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
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

    this.currentTabIndex = 0;
    if (!this.isLandscape) {
      this.tabsController.changeIndex(0);
    }
  }

  private landscapeSideMargin(): number {
    return this.isLandscape ? this.fontSize * 1.5 : 0;
  }

  private updateLandscapeFromArea(area: Area): void {
    const width: number = lengthToNumber(area.width);
    const height: number = lengthToNumber(area.height);
    const next: boolean = height > 0 && width > height;
    if (this.isLandscape !== next) {
      this.isLandscape = next;
    }
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private async loadThemeSetting(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.themeId = 'dark';
      this.theme = getAppThemeTokens(this.themeId);
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('theme', 'dark'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'dark',
      );
    const normalizedTheme: AppThemeId = (saved === 'light' || saved === 'reference' || saved === 'coo') ? 'light' : 'dark';
    this.themeId = normalizedTheme;
    this.theme = getAppThemeTokens(this.themeId);
    if (saved !== this.themeId) {
      await this.saveThemeSetting(this.themeId);
    }
  }

  private async saveThemeSetting(next: AppThemeId): Promise<void> {
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
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.orientationMode = 'portrait';
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('orientationMode', 'portrait'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'portrait',
      );
    if (saved === 'landscape' || saved === 'auto') {
      this.orientationMode = saved;
    } else {
      this.orientationMode = 'portrait';
    }
  }

  private async saveOrientationModeSetting(next: 'portrait' | 'landscape' | 'auto'): Promise<void> {
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
    let orientation: window.Orientation;
    if (mode === 'landscape') {
      orientation = window.Orientation.LANDSCAPE;
    } else if (mode === 'auto') {
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
    const recentStr: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('recentDocIds', '[]'))
      .then((v: ValueType): string => typeof v === 'string' ? v : '[]', (): string => '[]');

    const parsedFavorites: Array<string> = JSON.parse(favoriteStr) as Array<string>;
    const parsedRecent: Array<string> = JSON.parse(recentStr) as Array<string>;
    this.favoriteDocIds = parsedFavorites;
    this.recentDocIds = parsedRecent;
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

  private async openDoc(docId: string, switchToReadTab: boolean = true): Promise<void> {
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
        this.listScroller.scrollToIndex(0);
        this.listSearchScroller.scrollToIndex(0);
        if (switchToReadTab) {
          this.currentTabIndex = 1;
          if (!this.isLandscape) {
            this.tabsController.changeIndex(1);
          }
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
        this.listScroller.scrollToIndex(0);
        this.listSearchScroller.scrollToIndex(0);
        this.currentTabIndex = 2;
        if (!this.isLandscape) {
          this.tabsController.changeIndex(2);
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
    this.iconErrorKeys = [];
    this.errorText = '';
    this.showTocPanel = false;

    // 保存设置不应阻塞目录清单切换
    this.saveLangSetting(next);
    await this.loadManifest(true);
    await this.loadManifestCounts();
  }

  private async switchTheme(next: AppThemeId): Promise<void> {
    if (this.themeId === next) return;
    this.themeId = next;
    this.theme = getAppThemeTokens(next);
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
        this.docs = (manifest.docs ?? []).map((doc: ReferenceDocSummary): ReferenceDocSummary => ({
          id: doc.id,
          name: doc.name || doc.title || doc.id,
          title: doc.title || doc.name || doc.id,
          icon: doc.icon,
          file: doc.file,
          sectionCount: doc.sectionCount,
          cardCount: doc.cardCount,
        }));
        this.rebuildCatalogSearchResults();
        if (autoOpenFirst && !this.selectedDocId && this.docs.length > 0) {
          await this.openDoc(this.docs[0].id, false);
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
      (manifest: ReferenceManifest): number => (manifest.docs ?? []).length,
      (): number => -1,
    );
    const en = repo.getManifestByLang('en').then(
      (manifest: ReferenceManifest): number => (manifest.docs ?? []).length,
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

  async aboutToAppear(): Promise<void> {
    const launchParams: LaunchParams | undefined = peekLaunchParams();
    const launchAction: string = launchParams?.launchAction ?? '';
    const skipAutoOpenFirst: boolean = launchAction === LAUNCH_ACTION_OPEN_RECENT_DOCS;

    await this.loadThemeSetting();
    await this.loadLangSetting();
    await this.loadOrientationModeSetting();
    await this.loadLearningModeSetting();
    await this.loadFavoriteAndRecentDocs();
    await this.loadManifest(!skipAutoOpenFirst);
    await this.loadManifestCounts();
    await this.loadQuizRecord();
    await this.loadOnlineMdLinks();
    await this.loadLocalMdLinks();
    await this.consumeNotificationLaunchIfAny();
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
    this.onlineMdLinks = this.mergeDefaultOnlineMdLink(stored);
    await this.rebuildOnlineMdDocs();
  }

  private async loadLocalMdLinks(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const stored = await this.localMdRepository.getLinks(host);
    this.localMdLinks = stored;
    await this.rebuildLocalMdDocs();
  }

  private mergeDefaultOnlineMdLink(links: Array<OnlineMdLink>): Array<OnlineMdLink> {
    const normalized = DEFAULT_ONLINE_MD_URL.trim();
    for (let i = 0; i < links.length; i++) {
      const url = (links[i]?.url ?? '').trim();
      if (url === normalized) {
        return links;
      }
    }
    const defaultLink: OnlineMdLink = {
      id: DEFAULT_ONLINE_MD_LINK_ID,
      url: DEFAULT_ONLINE_MD_URL,
      name: DEFAULT_ONLINE_MD_NAME,
      addedTime: 0,
    };
    return [defaultLink, ...links];
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
      const cachedUrl: string = (cachedDoc.source?.url ?? '').trim();
      const defaultUrl: string = DEFAULT_ONLINE_MD_URL.trim();
      if (linkId === DEFAULT_ONLINE_MD_LINK_ID && cachedUrl && defaultUrl && cachedUrl !== defaultUrl) {
        await this.onlineMdRepository.deleteDocCache(host, linkId);
      } else {
        this.onlineMdDocCache.set(linkId, cachedDoc);
        return cachedDoc;
      }
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
        const cachedUrl: string = (cachedDoc.source?.url ?? '').trim();
        const defaultUrl: string = DEFAULT_ONLINE_MD_URL.trim();
        if (linkId === DEFAULT_ONLINE_MD_LINK_ID && cachedUrl && defaultUrl && cachedUrl !== defaultUrl) {
          await this.onlineMdRepository.deleteDocCache(host, linkId);
          this.onlineMdDocCache.delete(linkId);
        } else {
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
    this.onlineMdLinks = this.mergeDefaultOnlineMdLink(stored);
    await this.rebuildOnlineMdDocs();

    this.onlineMdParsing = false;
    this.onlineMdInputUrl = '';
    this.onlineMdParseResult = this.t(
      `解析成功：${doc.name}（${doc.sections.length} 章节，${doc.cards.length} 卡片）`,
      `Parse success: ${doc.name} (${doc.sections.length} sections, ${doc.cards.length} cards)`
    );
  }

  private async removeOnlineMd(linkId: string): Promise<void> {
    if (linkId === DEFAULT_ONLINE_MD_LINK_ID) return;
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    await this.onlineMdRepository.removeLink(host, linkId);
    await this.onlineMdRepository.deleteDocCache(host, linkId);
    this.onlineMdDocCache.delete(linkId);

    const stored = await this.onlineMdRepository.getLinks(host);
    this.onlineMdLinks = this.mergeDefaultOnlineMdLink(stored);
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
    this.currentTabIndex = 1;
    if (!this.isLandscape) {
      this.tabsController.changeIndex(1);
    }
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
    this.currentTabIndex = 2;
    if (!this.isLandscape) {
      this.tabsController.changeIndex(2);
    }
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
    this.currentTabIndex = 1;
    if (!this.isLandscape) {
      this.tabsController.changeIndex(1);
    }
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
    this.currentTabIndex = 2;
    if (!this.isLandscape) {
      this.tabsController.changeIndex(2);
    }
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
    this.quizMode = 'result';
  }

  private resetQuiz(): void {
    this.quizMode = 'idle';
    this.quizQuestions = [];
    this.quizCurrentIndex = 0;
    this.quizAnswers = [];
    this.quizSelectedOptionIndex = -1;
    this.quizShowAnswer = false;
  }

  onBackPress(): boolean {
    if (this.showTocPanel) {
      this.stopAllTextInputEditing();
      this.showTocPanel = false;
      return true;
    }
    if (this.currentTabIndex !== 0) {
      this.currentTabIndex = 0;
      if (!this.isLandscape) {
        this.tabsController.changeIndex(0);
      }
      return true;
    }
    return true;
  }

  private getTabLabel(index: number): string {
    if (index === 0) return this.t('目录', 'Catalog');
    if (index === 1) return this.t('备忘清单', 'Cheatsheet');
    if (index === 2) return this.t('测验', 'Quiz');
    return this.t('设置', 'Settings');
  }

  @Builder
  private TabBarItem(index: number): void {
    Column() {
      Text(this.getTabLabel(index))
        .fontSize(this.fontSize * 1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal);
    }
    .padding({ top: this.fontSize * 0.2, bottom: this.fontSize * 0, left: this.fontSize * 0.5, right: this.fontSize * 0.5 });
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
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        favoriteDocIds: this.favoriteDocIds,
        recentDocIds: this.recentDocIds,
        iconErrorKeys: this.iconErrorKeys,
        catalogSearchInputController: this.catalogSearchInputController,
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
        listScroller: this.listScroller,
        listSearchScroller: this.listSearchScroller,
        listSectionNavScroller: this.listSectionNavScroller,
        listCardNavScroller: this.listCardNavScroller,
        docSearchInputController: this.docSearchInputController,
        onToggleDocFavorite: (docId: string): void => { this.toggleDocFavorite(docId); },
        onShowTocPanel: (): void => { this.stopAllTextInputEditing(); this.showTocPanel = true; },
        onRebuildSearchResults: (): void => { this.rebuildSearchResults(); },
      });
    } else if (this.currentTabIndex === 2) {
      QuizTab({
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
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
      });
    } else {
      SettingsTab({
        theme: this.theme,
        fontSize: this.fontSize,
        lang: this.lang,
        isLandscape: this.isLandscape,
        themeId: this.themeId,
        orientationMode: this.orientationMode,
        learningModeEnabled: this.learningModeEnabled,
        zhDocCount: this.zhDocCount,
        enDocCount: this.enDocCount,
        onlineMdInputUrl: this.onlineMdInputUrl,
        onlineMdParsing: this.onlineMdParsing,
        onlineMdParseResult: this.onlineMdParseResult,
        onlineMdLinks: this.onlineMdLinks,
        onlineMdCopySuccess: this.onlineMdCopySuccess,
        localMdImporting: this.localMdImporting,
        localMdImportResult: this.localMdImportResult,
        localMdLinks: this.localMdLinks,
        localMdCopySuccess: this.localMdCopySuccess,
        onSwitchOrientationMode: (mode: 'portrait' | 'landscape' | 'auto'): void => { this.switchOrientationMode(mode); },
        onSwitchLang: (lang: ReferenceLang): void => { this.switchLang(lang); },
        onSwitchTheme: (theme: AppThemeId): void => { this.switchTheme(theme); },
        onToggleLearningMode: (enabled: boolean): void => { this.toggleLearningMode(enabled); },
        onParseAndAddOnlineMd: (): void => { this.parseAndAddOnlineMd(); },
        onRemoveOnlineMd: (linkId: string): void => { this.removeOnlineMd(linkId); },
        onCopyOnlineMdUrl: (url: string): void => { this.copyOnlineMdUrl(url); },
        onImportLocalMarkdown: (): void => { this.importLocalMarkdown(); },
        onRemoveLocalMd: (linkId: string): void => { this.removeLocalMd(linkId); },
        onCopyLocalMdUri: (uri: string): void => { this.copyLocalMdUri(uri); },
      });
    }
  }

  build() {
    Stack() {
      if (this.isLandscape) {
        this.CurrentTabContent();
      } else {
        Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex, controller: this.tabsController }) {
          TabContent() {
            DocListTab({
              currentTabIndex: this.currentTabIndex,
              loading: this.loading,
              errorText: this.errorText,
              catalogSearchQuery: this.catalogSearchQuery,
              catalogSearchResults: this.catalogSearchResults,
              theme: this.theme,
              fontSize: this.fontSize,
              lang: this.lang,
              isLandscape: this.isLandscape,
              favoriteDocIds: this.favoriteDocIds,
              recentDocIds: this.recentDocIds,
              iconErrorKeys: this.iconErrorKeys,
              catalogSearchInputController: this.catalogSearchInputController,
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
              listScroller: this.listScroller,
              listSearchScroller: this.listSearchScroller,
              listSectionNavScroller: this.listSectionNavScroller,
              listCardNavScroller: this.listCardNavScroller,
              docSearchInputController: this.docSearchInputController,
              onToggleDocFavorite: (docId: string): void => { this.toggleDocFavorite(docId); },
              onShowTocPanel: (): void => { this.stopAllTextInputEditing(); this.showTocPanel = true; },
              onRebuildSearchResults: (): void => { this.rebuildSearchResults(); },
            });
          }
          .tabBar(this.TabBarItem(1));

          TabContent() {
            QuizTab({
              theme: this.theme,
              fontSize: this.fontSize,
              lang: this.lang,
              isLandscape: this.isLandscape,
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
            });
          }
          .tabBar(this.TabBarItem(2));

          TabContent() {
            SettingsTab({
              theme: this.theme,
              fontSize: this.fontSize,
              lang: this.lang,
              isLandscape: this.isLandscape,
              themeId: this.themeId,
              orientationMode: this.orientationMode,
              learningModeEnabled: this.learningModeEnabled,
              zhDocCount: this.zhDocCount,
              enDocCount: this.enDocCount,
              onlineMdInputUrl: this.onlineMdInputUrl,
              onlineMdParsing: this.onlineMdParsing,
              onlineMdParseResult: this.onlineMdParseResult,
              onlineMdLinks: this.onlineMdLinks,
              onlineMdCopySuccess: this.onlineMdCopySuccess,
              localMdImporting: this.localMdImporting,
              localMdImportResult: this.localMdImportResult,
              localMdLinks: this.localMdLinks,
              localMdCopySuccess: this.localMdCopySuccess,
              onSwitchOrientationMode: (mode: 'portrait' | 'landscape' | 'auto'): void => { this.switchOrientationMode(mode); },
              onSwitchLang: (lang: ReferenceLang): void => { this.switchLang(lang); },
              onSwitchTheme: (theme: AppThemeId): void => { this.switchTheme(theme); },
              onToggleLearningMode: (enabled: boolean): void => { this.toggleLearningMode(enabled); },
              onParseAndAddOnlineMd: (): void => { this.parseAndAddOnlineMd(); },
              onRemoveOnlineMd: (linkId: string): void => { this.removeOnlineMd(linkId); },
              onCopyOnlineMdUrl: (url: string): void => { this.copyOnlineMdUrl(url); },
              onImportLocalMarkdown: (): void => { this.importLocalMarkdown(); },
              onRemoveLocalMd: (linkId: string): void => { this.removeLocalMd(linkId); },
              onCopyLocalMdUri: (uri: string): void => { this.copyLocalMdUri(uri); },
            });
          }
          .tabBar(this.TabBarItem(3));
        }
        .scrollable(false)
        .barBackgroundColor(this.theme.surfaceBackgroundColor)
        .onChange((index: number) => {
          this.currentTabIndex = index;
        });
      }

      if (this.showTocPanel) {
        TocPanel({
          theme: this.theme,
          fontSize: this.fontSize,
          lang: this.lang,
          selectedDocId: this.selectedDocId,
          sectionCards: this.sectionCards,
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
    }
    .backgroundColor(this.theme.pageBackgroundColor)
    .onAreaChange((_: Area, area: Area) => {
      this.updateLandscapeFromArea(area);
    })
    .padding({ left: this.landscapeSideMargin(), right: this.landscapeSideMargin() })
    .width('100%')
    .height('100%');
  }
}
