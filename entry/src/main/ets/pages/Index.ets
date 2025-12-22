import preferences from '@ohos.data.preferences';
import pasteboard from '@ohos.pasteboard';
import { window } from '@kit.ArkUI';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeId, AppThemeTokens } from '../common/appTheme';
import { decodeIfEncoded } from '../common/encodedContent';
import { ReferenceCard } from '../components/ReferenceCard';
import { openExternalLink } from '../common/openExternalLink';
import { EbbinghausReminderManager } from '../common/ebinghausReminder';
import type { QuizQuestion, QuizAnswer, QuizSession, QuizRecord, QuizOption } from '../common/quizModels';
import { generateQuizSessionId } from '../common/quizModels';
import { extractQuestionsFromDoc, selectRandomQuestions, calculateScore } from '../common/quizUtils';
import { QuizRepository } from '../common/quizRepository';
import { OnlineMdRepository } from '../common/onlineMdRepository';
import type { OnlineMdLink } from '../common/onlineMdModels';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

interface SectionWithCards {
  section: ReferenceSection;
  cards: Array<ReferenceCardData>;
}

interface CardMargin {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

function makeCardMargin(fontSize: number): CardMargin {
  const margin: CardMargin = {
    left: fontSize * 1,
    right: fontSize * 1,
    top: fontSize * 0.5,
    bottom: fontSize * 0.5
  };
  return margin;
}

const DEFAULT_ONLINE_MD_LINK_ID: string = 'online_default_quickreference';
const DEFAULT_ONLINE_MD_URL: string = 'https://reference.jqknono.com/mds/zh/quickreference.md';
const DEFAULT_ONLINE_MD_NAME: string = 'Quick Reference 备忘清单';

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
  private sectionNavScroller: Scroller = new Scroller();
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
  @State private ebbinghausReminderEnabled: boolean = false;
  @State private ebbinghausActiveCount: number = 0;
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

  private lengthToNumber(value: Length): number {
    if (typeof value === 'number') return value;
    const parsed: number = Number.parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private stopAllTextInputEditing(): void {
    this.catalogSearchInputController.stopEditing();
    this.docSearchInputController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
  }

  private landscapeSideMargin(): number {
    return this.isLandscape ? this.fontSize * 1.5 : 0;
  }

  private tabPadding(): Padding {
    const base: number = this.fontSize * 1;
    return this.isLandscape
      ? { left: base, right: base, top: base, bottom: 0 }
      : { left: base, right: base, top: base, bottom: base };
  }

  private toHexColorString(color: number): string {
    const value: number = color >>> 0;
    const hex: string = value.toString(16);
    const normalized: string = (hex.length <= 6 ? hex.padStart(6, '0') : hex.padStart(8, '0'));
    return `#${normalized}`;
  }

  private updateLandscapeFromArea(area: Area): void {
    const width: number = this.lengthToNumber(area.width);
    const height: number = this.lengthToNumber(area.height);
    const next: boolean = height > 0 && width > height;
    if (this.isLandscape !== next) {
      this.isLandscape = next;
    }
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private iconKey(docId: string, icon: string | undefined): string {
    if (!icon) return docId;
    const trimmed = icon.trim();
    if (!trimmed) return docId;
    if (trimmed.startsWith('data:')) return docId;
    return `${docId}:${trimmed}`;
  }

  private hasIconError(iconKey: string): boolean {
    if (!iconKey) return false;
    return this.iconErrorKeys.indexOf(iconKey) >= 0;
  }

  private markIconError(iconKey: string): void {
    if (!iconKey) return;
    if (this.hasIconError(iconKey)) return;
    const next: Array<string> = this.iconErrorKeys.slice();
    next.push(iconKey);
    this.iconErrorKeys = next;
  }

  private isRemoteIcon(icon: string | undefined): boolean {
    const s: string = (icon ?? '').trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  private trimmedIcon(icon: string | undefined): string {
    return (icon ?? '').trim();
  }

  private isRawfileIcon(icon: string | undefined): boolean {
    const s = this.trimmedIcon(icon);
    return s.startsWith('reference/');
  }

  private isSvgIcon(icon: string | undefined): boolean {
    const s: string = this.trimmedIcon(icon).toLowerCase();
    return s.endsWith('.svg');
  }

  private canShowLocalIcon(docId: string, icon: string | undefined): boolean {
    const s = this.trimmedIcon(icon);
    if (!s) return false;
    if (this.isRemoteIcon(s)) return false;
    return !this.hasIconError(this.iconKey(docId, s));
  }

  private getAvatarText(label: string): string {
    const trimmed: string = (label ?? '').trim();
    if (!trimmed) return '?';
    const chars: Array<string> = Array.from(trimmed);
    let picked: string = chars[0] ?? '?';
    if (picked === '.' && chars.length > 1) {
      picked = chars[1];
    }
    return picked.toUpperCase();
  }

  @Builder
  private DocAvatar(docId: string, label: string, icon: string | undefined, size: number, radius: number): void {
    if (this.canShowLocalIcon(docId, icon)) {
      if (this.isRawfileIcon(icon)) {
        if (this.isSvgIcon(icon)) {
          ForEach([this.iconKey(docId, this.trimmedIcon(icon))], (_: string) => {
            Image($rawfile(this.trimmedIcon(icon)))
              .width(size)
              .height(size)
              .syncLoad(true)
              .fillColor(this.theme.avatarTextColor)
              .onError(() => this.markIconError(this.iconKey(docId, this.trimmedIcon(icon))));
          }, (k: string) => k);
        } else {
          ForEach([this.iconKey(docId, this.trimmedIcon(icon))], (_: string) => {
            Image($rawfile(this.trimmedIcon(icon)))
              .width(size)
              .height(size)
              .syncLoad(true)
              .onError(() => this.markIconError(this.iconKey(docId, this.trimmedIcon(icon))));
          }, (k: string) => k);
        }
      } else {
        if (this.isSvgIcon(icon)) {
          ForEach([this.iconKey(docId, this.trimmedIcon(icon))], (_: string) => {
            Image(this.trimmedIcon(icon))
              .width(size)
              .height(size)
              .syncLoad(true)
              .fillColor(this.theme.avatarTextColor)
              .onError(() => this.markIconError(this.iconKey(docId, this.trimmedIcon(icon))));
          }, (k: string) => k);
        } else {
          ForEach([this.iconKey(docId, this.trimmedIcon(icon))], (_: string) => {
            Image(this.trimmedIcon(icon))
              .width(size)
              .height(size)
              .syncLoad(true)
              .onError(() => this.markIconError(this.iconKey(docId, this.trimmedIcon(icon))));
          }, (k: string) => k);
        }
      }
    } else {
      Text(this.getAvatarText(label))
        .width(size)
        .height(size)
        .textAlign(TextAlign.Center)
        .fontSize(Math.floor(size * 0.4))
        .fontColor(this.theme.avatarTextColor)
        .backgroundColor(this.theme.avatarBackgroundColor)
        .borderRadius(radius);
    }
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

  private async loadEbbinghausReminderSetting(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) {
      this.ebbinghausReminderEnabled = false;
      return;
    }
    const saved: boolean = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('ebbinghausReminder', false))
      .then(
        (value: ValueType): boolean => value === true || value === 'true',
        (): boolean => false,
      );
    this.ebbinghausReminderEnabled = saved;
    await EbbinghausReminderManager.hydrate(host);
    this.refreshEbbinghausActiveCount();
  }

  private async saveEbbinghausReminderSetting(enabled: boolean): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) return;
    const prefs: Preferences | undefined = await Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(host, 'settings'))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
    if (!prefs) return;
    await Promise.resolve()
      .then((): Promise<void> => prefs.put('ebbinghausReminder', enabled))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  private refreshEbbinghausActiveCount(): void {
    this.ebbinghausActiveCount = EbbinghausReminderManager.getActiveReminderCount();
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

  private async toggleEbbinghausReminder(enabled: boolean): Promise<void> {
    if (this.ebbinghausReminderEnabled === enabled) return;
    this.ebbinghausReminderEnabled = enabled;
    await this.saveEbbinghausReminderSetting(enabled);

    const host = this.getUIContext().getHostContext();
    if (!host) return;
    if (enabled) {
      await EbbinghausReminderManager.cancelAllReminders(host);
      await EbbinghausReminderManager.publishReminders(host, this.lang);
    } else {
      await EbbinghausReminderManager.cancelAllReminders(host);
    }
    this.refreshEbbinghausActiveCount();
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

  private normalizeSearchTokens(query: string): Array<string> {
    const trimmed = query.trim();
    if (!trimmed) return [];
    return trimmed
      .split(/\s+/)
      .map((part: string): string => part.trim().toLowerCase())
      .filter((part: string): boolean => !!part);
  }

  private cardMatchesTokens(card: ReferenceCardData, tokens: Array<string>): boolean {
    if (tokens.length === 0) return true;
    const encoded: boolean = card.encoded === true;
    const haystack = [
      decodeIfEncoded(card.title ?? '', encoded),
      decodeIfEncoded(card.body ?? '', encoded),
      decodeIfEncoded(card.front ?? '', encoded),
      decodeIfEncoded(card.back ?? '', encoded),
      decodeIfEncoded(card.code ?? '', encoded),
    ]
      .join('\n')
      .toLowerCase();

    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (!token) continue;
      if (haystack.indexOf(token) < 0) return false;
    }
    return true;
  }

  private rebuildSearchResults(): void {
    const doc = this.selectedDoc;
    const tokens = this.normalizeSearchTokens(this.searchQuery);
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
      if (!this.cardMatchesTokens(card, tokens)) continue;
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

    results.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => this.compareCatalogDocs(a, b));
    this.catalogSearchResults = results;
  }

  private catalogDocSortKey(doc: ReferenceDocSummary): string {
    return (doc.name || doc.title || doc.id || '').trim().toLowerCase();
  }

  private compareCatalogDocs(a: ReferenceDocSummary, b: ReferenceDocSummary): number {
    const ak = this.catalogDocSortKey(a);
    const bk = this.catalogDocSortKey(b);
    if (ak < bk) return -1;
    if (ak > bk) return 1;

    const aid = (a.id ?? '').toLowerCase();
    const bid = (b.id ?? '').toLowerCase();
    if (aid < bid) return -1;
    if (aid > bid) return 1;

    const af = (a.file ?? '').toLowerCase();
    const bf = (b.file ?? '').toLowerCase();
    if (af < bf) return -1;
    if (af > bf) return 1;
    return 0;
  }

  private getCatalogDocsForDisplay(): Array<ReferenceDocSummary> {
    const merged: Array<ReferenceDocSummary> = [];
    for (let i = 0; i < this.docs.length; i++) {
      merged.push(this.docs[i]);
    }
    for (let i = 0; i < this.onlineMdDocs.length; i++) {
      merged.push(this.onlineMdDocs[i]);
    }
    merged.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => this.compareCatalogDocs(a, b));
    return merged;
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
        // 跳转到测验标签页
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
    this.lang = next;
    await this.saveLangSetting(next);
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

  private formatDocCount(count: number): string {
    if (!Number.isFinite(count) || count < 0) return this.t('未知', 'N/A');
    return `${Math.floor(count)}`;
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
    await this.loadThemeSetting();
    await this.loadLangSetting();
    await this.loadOrientationModeSetting();
    await this.loadEbbinghausReminderSetting();
    await this.loadLearningModeSetting();
    await this.loadManifest();
    await this.loadManifestCounts();
    await this.loadQuizRecord();
    await this.loadOnlineMdLinks();
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

  private isDefaultOnlineMdLink(link: OnlineMdLink): boolean {
    if (!link) return false;
    if (link.id === DEFAULT_ONLINE_MD_LINK_ID) return true;
    return (link.url ?? '').trim() === DEFAULT_ONLINE_MD_URL.trim();
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
        `仅支持 Markdown 文件：URL 必须以 .md 结尾（当前：${url}）`,
        `Only Markdown files are supported: URL must end with .md (current: ${url})`
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

  private isOnlineDoc(docId: string): boolean {
    return docId.startsWith('online_');
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
    // 跳转到测验标签页
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
    const questions = extractQuestionsFromDoc(this.selectedDoc);
    this.quizAvailableCount = questions.length;
  }

  private async startQuiz(questionCount: number): Promise<void> {
    if (!this.selectedDoc) return;

    const allQuestions = extractQuestionsFromDoc(this.selectedDoc);
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
    if (!this.isLandscape && this.currentTabIndex !== 0) {
      this.currentTabIndex = 0;
      this.tabsController.changeIndex(0);
      return true;
    }
    return true;
  }

  @Builder
  private DocListTab(): void {
    Column({ space: this.fontSize * 0.6 }) {
      Text(this.t('开发速查', 'Quick Reference'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.titleColor);

      if (!this.isLandscape) {
        Row({ space: this.fontSize * 0.6 }) {
        TextInput({
          text: this.catalogSearchQuery,
          placeholder: this.t('搜索文档…', 'Search docs…'),
          controller: this.catalogSearchInputController,
        })
          .layoutWeight(1)
          .fontSize(this.fontSize)
          .fontColor(this.theme.titleColor)
          .placeholderColor(this.theme.mutedTextColor)
          .enableAutoFill(false)
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .border({ width: 1, color: this.theme.borderColor })
          .borderRadius(this.fontSize * 0.8)
          .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.6, bottom: this.fontSize * 0.6 })
          .onChange((value: string) => {
            this.catalogSearchQuery = value;
            this.rebuildCatalogSearchResults();
          });

        if (this.catalogSearchQuery.trim()) {
          Text(this.t('清除', 'Clear'))
            .fontSize(this.fontSize * 0.8)
            .fontColor(this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .border({ width: 1, color: this.theme.borderColor })
            .borderRadius(this.fontSize * 0.8)
            .onClick(() => {
              this.catalogSearchQuery = '';
              this.catalogSearchResults = [];
            });
        }
        }
      }

      if (this.loading) {
        Text(this.t('加载中…', 'Loading…')).fontColor(this.theme.mutedTextColor);
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(this.theme.dangerTextColor).maxLines(6);
      }

      if (this.catalogSearchQuery.trim() && this.catalogSearchResults.length === 0) {
        Text(this.t('没有匹配的文档', 'No matching docs.')).fontColor(this.theme.mutedTextColor);
      }

      List() {
        ForEach(this.catalogSearchQuery.trim() ? this.catalogSearchResults : this.getCatalogDocsForDisplay(), (doc: ReferenceDocSummary) => {
          ListItem() {
            Stack({ alignContent: Alignment.TopStart }) {
              Row({ space: this.fontSize * 0.8 }) {
                this.DocAvatar(doc.id, doc.name || doc.id, doc.icon, this.fontSize * 2.5, 0);

                Column({ space: this.fontSize * 0.2 }) {
                  Text(doc.name || doc.id).fontSize(this.fontSize * 1).fontColor(this.theme.titleColor);

                  if (doc.title && doc.title !== doc.name) {
                    Text(doc.title)
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.mutedTextColor)
                      .maxLines(2);
                  }

                  Text(this.t(`${doc.sectionCount} 章节 · ${doc.cardCount} 卡片`, `${doc.sectionCount} sections · ${doc.cardCount} cards`))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor);
                }.layoutWeight(1);

                if (this.isLandscape) {
                  // 横屏：左右摆放
                  Row({ space: this.fontSize * 0.8 }) {
                    Text(this.t('打开', 'Open'))
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                      .border({ width: 1, color: this.theme.accentColor })
                      .borderRadius(this.fontSize * 0.4)
                      .onClick(() => this.isOnlineDoc(doc.id) ? this.openOnlineDoc(doc.id) : this.openDoc(doc.id, true));
                    Text(this.t('测验', 'Quiz'))
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                      .border({ width: 1, color: this.theme.accentColor })
                      .borderRadius(this.fontSize * 0.4)
                      .onClick(() => this.isOnlineDoc(doc.id) ? this.openOnlineDocAndQuiz(doc.id) : this.openDocAndQuiz(doc.id));
                  }
                } else {
                  // 竖屏：上下堆叠
                  Column({ space: this.fontSize * 0.5 }) {
                    Text(this.t('打开', 'Open'))
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                      .border({ width: 1, color: this.theme.accentColor })
                      .borderRadius(this.fontSize * 0.4)
                      .onClick(() => this.isOnlineDoc(doc.id) ? this.openOnlineDoc(doc.id) : this.openDoc(doc.id, true));
                    Text(this.t('测验', 'Quiz'))
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                      .border({ width: 1, color: this.theme.accentColor })
                      .borderRadius(this.fontSize * 0.4)
                      .onClick(() => this.isOnlineDoc(doc.id) ? this.openOnlineDocAndQuiz(doc.id) : this.openDocAndQuiz(doc.id));
                  }
                  .alignItems(HorizontalAlign.End);
                }
              }
              .padding(this.fontSize * 1)
              .width('100%');

              if (this.isOnlineDoc(doc.id)) {
                // 在线标记 - 左上角
                Text(this.t('在线', 'Online'))
                  .fontSize(this.fontSize * 0.65)
                  .fontColor(0xffffffff)
                  .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                  .backgroundColor(this.theme.accentColor)
                  .borderRadius({
                    topLeft: this.fontSize * 0.7,
                    topRight: this.fontSize * 0,
                    bottomLeft: this.fontSize * 0,
                    bottomRight: this.fontSize * 0.4
                  });
              }
            }
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.8);
          }
          .margin({ bottom: this.fontSize * 0.6 });
        }, (doc: ReferenceDocSummary) => this.isOnlineDoc(doc.id) ? `online:${doc.id}` : `${this.lang}:${doc.id}`);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 });
    }
    .padding(this.tabPadding())
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  @Builder
  private ReadTab(): void {
    Column({ space: this.fontSize * 0.6 }) {
      Row({ space: this.fontSize * 0.6 }) {
        if (this.selectedDoc) {
          ForEach([this.selectedDocAvatarVersion], (_: number) => {
            this.DocAvatar(
              this.selectedDocId,
              this.selectedDoc?.name || this.selectedDoc?.title || this.selectedDocId,
              this.selectedDocIcon || undefined,
              this.fontSize * 1.5,
              0,
            );
          }, (k: number) => `${k}`);
        }

        Column({ space: this.fontSize * 0.1 }) {
          Text(this.selectedDoc ? (this.selectedDoc.name || this.selectedDoc.title) : this.t('未选择', 'No selection'))
            .fontSize(this.fontSize * 1.2)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleColor);

          if (this.selectedDoc && this.selectedDoc.title && this.selectedDoc.title !== this.selectedDoc.name) {
            Text(this.selectedDoc.title).fontSize(this.fontSize * 0.8).fontColor(this.theme.mutedTextColor).maxLines(2);
          }
        }
        .layoutWeight(1);

        Text(this.t('目录', 'TOC'))
          .fontSize(this.fontSize * 1)
          .fontColor(this.theme.accentColor)
          .onClick(() => {
            this.stopAllTextInputEditing();
            this.showTocPanel = true;
          });
      }
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.4 });

      if (this.selectedDoc && !this.isLandscape) {
        Row({ space: this.fontSize * 0.6 }) {
          TextInput({
            text: this.searchQuery,
            placeholder: this.t('搜索当前文档…', 'Search current doc…'),
            controller: this.docSearchInputController,
          })
            .layoutWeight(1)
            .fontSize(this.fontSize * 1)
            .fontColor(this.theme.titleColor)
            .placeholderColor(this.theme.mutedTextColor)
            .enableAutoFill(false)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .border({ width: 1, color: this.theme.borderColor })
            .borderRadius(this.fontSize * 0.8)
            .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
            .onChange((value: string) => {
              this.searchQuery = value;
              this.rebuildSearchResults();
            });

          if (this.searchQuery.trim()) {
            Text(this.t('清除', 'Clear'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.theme.mutedTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .border({ width: 1, color: this.theme.borderColor })
              .borderRadius(this.fontSize * 0.8)
              .onClick(() => {
                this.searchQuery = '';
                this.rebuildSearchResults();
              });
          }
        }
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
      }

      if (this.loading) {
        Text(this.t('加载中…', 'Loading…')).fontColor(this.theme.mutedTextColor).padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(this.theme.dangerTextColor).padding({ left: this.fontSize * 1, right: this.fontSize * 1 }).maxLines(6);
      }

      if (!this.selectedDoc) {
        Text(this.t('请先在"目录"中打开一个文档', 'Open a doc in "Catalog" first.')).fontColor(this.theme.mutedTextColor).padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
      }

      if (this.searchQuery.trim()) {
        if (this.searchResultCount === 0) {
          Text(this.t('没有匹配结果', 'No results.')).fontColor(this.theme.mutedTextColor).padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
        } else {
          Text(this.t(`${this.searchResultCount} 条结果`, `${this.searchResultCount} results`))
            .fontSize(this.fontSize * 0.8)
            .fontColor(this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
        }

        List({ scroller: this.listSearchScroller }) {
          ForEach(this.searchSectionCards, (group: SectionWithCards, groupIndex: number) => {
            ListItemGroup() {
              ListItem() {
                Row({ space: this.fontSize * 0.4 }) {
                  Text('#')
                    .fontSize(this.fontSize * 1)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.sectionTitleColor);
                  Text(`${group.section.title} (${group.cards.length})`)
                    .fontSize(this.fontSize)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.sectionTitleColor);
                }
                .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.4 });
              }

              ForEach(group.cards, (card: ReferenceCardData) => {
                ListItem() {
                  ReferenceCard({
                    card,
                    theme: this.theme,
                    fontSize: this.fontSize,
                    unboundedTableColumns: this.isLandscape,
                    learningMode: this.learningModeEnabled,
                    hostContext: this.getUIContext().getHostContext(),
                    margin: makeCardMargin(this.fontSize),
                  })
                  ;
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:search:${card.id}:${this.learningModeEnabled}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:search:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 });

        if (this.searchSectionCards.length > 0) {
          Column() {
            Scroll(this.listSectionNavScroller) {
              Row({ space: this.fontSize * 0.5 }) {
                ForEach(this.searchSectionCards, (group: SectionWithCards, groupIndex: number) => {
                  Text(group.section.title)
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.searchNavSectionIndex === groupIndex ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                    .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
                    .backgroundColor(this.searchNavSectionIndex === groupIndex ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                    .borderRadius(this.fontSize * 66)
                    .onClick(() => {
                      this.searchNavSectionIndex = groupIndex;
                      this.listSearchScroller.scrollToItemInGroup(groupIndex, 0, true, ScrollAlign.START);
                    });
                }, (group: SectionWithCards) => `${this.selectedDocId}:search:nav:${group.section.id}:${this.searchNavSectionIndex}`);
              }
              .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.5, bottom: this.fontSize * 0.2 });
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off);

            Scroll(this.listCardNavScroller) {
              Row({ space: this.fontSize * 0.4 }) {
                ForEach(
                  this.searchSectionCards[this.searchNavSectionIndex]?.cards ?? [],
                  (card: ReferenceCardData, cardIndex: number) => {
                    Text(this.getTocCardTitle(card))
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.mutedTextColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .constraintSize({ maxWidth: this.fontSize * 8 })
                      .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                      .backgroundColor(this.theme.chipBackgroundColor)
                      .borderRadius(this.fontSize * 0.4)
                      .onClick(() => {
                        this.listSearchScroller.scrollToItemInGroup(this.searchNavSectionIndex, cardIndex + 1, true, ScrollAlign.START);
                      });
                  },
                  (card: ReferenceCardData) => `${this.selectedDocId}:search:cardnav:${card.id}`
                );
              }
              .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.2, bottom: this.fontSize * 0.5 });
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off);
          }
          .backgroundColor(this.theme.surfaceMutedBackgroundColor);
        }
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
            ListItemGroup() {
              ListItem() {
                Row({ space: this.fontSize * 0.4 }) {
                  Text('#')
                    .fontSize(this.fontSize * 1)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.sectionTitleColor);
                  Text(group.section.title)
                    .fontSize(this.fontSize)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.sectionTitleColor);
                }
                .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.4 });
              }

              ForEach(group.cards, (card: ReferenceCardData, cardIndex: number) => {
                ListItem() {
                  ReferenceCard({
                    card,
                    theme: this.theme,
                    fontSize: this.fontSize,
                    unboundedTableColumns: this.isLandscape,
                    learningMode: this.learningModeEnabled,
                    hostContext: this.getUIContext().getHostContext(),
                    margin: makeCardMargin(this.fontSize),
                  })
                  ;
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:${card.id}:${this.learningModeEnabled}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 })
        .onAppear(() => {
          if (this.pendingTocScrollGroupIndex >= 0 && this.pendingTocScrollItemIndex >= 0) {
            const groupIndex: number = this.pendingTocScrollGroupIndex;
            const itemIndex: number = this.pendingTocScrollItemIndex;
            this.pendingTocScrollGroupIndex = -1;
            this.pendingTocScrollItemIndex = -1;
            this.listScroller.scrollToItemInGroup(groupIndex, itemIndex, true, ScrollAlign.START);
          }
        });
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  private getTocCardTitle(card: ReferenceCardData): string {
    const encoded = card.encoded === true;
    if (card.title) {
      return decodeIfEncoded(card.title, encoded);
    }
    if (card.kind === 'qa' && card.front) {
      const front = decodeIfEncoded(card.front, encoded);
      const firstLine = front.split('\n')[0] ?? '';
      return firstLine.substring(0, 50) || card.id;
    }
    if (card.body) {
      const body = decodeIfEncoded(card.body, encoded);
      const firstLine = body.split('\n')[0] ?? '';
      return firstLine.substring(0, 50) || card.id;
    }
    return card.id;
  }

  @Builder
  private TocPanel(): void {
    Column() {
      Column() {
        Row() {
          Text(this.t('目录', 'Table of Contents'))
            .fontSize(this.fontSize * 1.2)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleColor);
          Blank();
          Text(this.t('关闭', 'Close'))
            .fontSize(this.fontSize * 1)
            .fontColor(this.theme.accentColor)
            .onClick(() => {
              this.stopAllTextInputEditing();
              this.showTocPanel = false;
            });
        }
        .width('100%')
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.8 });

        List() {
          ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
            ListItemGroup() {
              ListItem() {
                Row({ space: this.fontSize * 0.4 }) {
                  Text('#')
                    .fontSize(this.fontSize)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.theme.sectionTitleColor);
                  Text(group.section.title)
                    .fontSize(this.fontSize * 1)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.sectionTitleColor);
                }
                .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.8, bottom: this.fontSize * 0.4 });
              }

              ForEach(group.cards, (card: ReferenceCardData, cardIndex: number) => {
                ListItem() {
                  Text(this.getTocCardTitle(card))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.textColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: this.fontSize * 1.87, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
                    .width('100%')
                    .onClick(() => {
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
                    });
                }
              }, (card: ReferenceCardData) => `toc:${this.selectedDocId}:${card.id}`);
            }
          }, (group: SectionWithCards) => `toc:${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 });
      }
      .width('100%')
      .height('70%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius({
        topLeft: this.fontSize * 1,
        topRight: this.fontSize * 1,
        bottomLeft: this.fontSize * 0,
        bottomRight: this.fontSize * 0
      });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.stopAllTextInputEditing();
      this.showTocPanel = false;
    });
  }

  @Builder
  private SettingsTab(): void {
    Scroll() {
      Column({ space: this.fontSize * 0.8 }) {
        Text(this.t('设置', 'Settings')).fontSize(this.fontSize * 1.25).fontWeight(FontWeight.Bold).fontColor(this.theme.titleColor);

      Column({ space: 0 }) {
        Row() {
          Text(this.t('屏幕方向', 'Orientation'))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 0.95);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('竖屏', 'Portrait'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchOrientationMode('portrait'));
            Text(this.t('横屏', 'Landscape'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchOrientationMode('landscape'));
            Text(this.t('自动', 'Auto'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.orientationMode === 'auto' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.orientationMode === 'auto' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchOrientationMode('auto'));
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });

        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row() {
          Text(this.t('语言', 'Language'))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 0.95);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('中文', '中文'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.lang === 'zh' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.lang === 'zh' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchLang('zh'));
            Text('English')
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.lang === 'en' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.lang === 'en' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchLang('en'));
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });

        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row() {
          Text(this.t('主题', 'Theme'))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 0.95);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('暗黑', 'Dark'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.themeId === 'dark' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.themeId === 'dark' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchTheme('dark'));
            Text(this.t('明亮', 'Light'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.themeId === 'light' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.themeId === 'light' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchTheme('light'));
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });
      }
      .width('100%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

      Column({ space: 0 }) {
        Row() {
          Column({ space: this.fontSize * 0.2 }) {
            Text(this.t('艾宾浩斯记忆提醒', 'Ebbinghaus Memory Reminder'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.95);
            Text(EbbinghausReminderManager.getIntervalDescription(this.lang))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.75)
              .opacity(0.7);
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Toggle({ type: ToggleType.Switch, isOn: this.ebbinghausReminderEnabled })
            .selectedColor(this.theme.accentColor)
            .onChange((isOn: boolean) => this.toggleEbbinghausReminder(isOn));
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });

        if (this.ebbinghausReminderEnabled) {
          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t(
              `当前活跃提醒：${this.ebbinghausActiveCount} 个`,
              `Active reminders: ${this.ebbinghausActiveCount}`
            ))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.85);
            Text(this.t(
              '开启后将在学习后的关键时间点发送通知，帮助您根据记忆曲线进行复习。',
              'When enabled, notifications will be sent at key time points after learning to help you review according to the memory curve.'
            ))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.8)
              .opacity(0.7);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.5, bottom: this.fontSize * 0.7 });
        }
      }
      .width('100%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

      Column({ space: 0 }) {
        Row() {
          Column({ space: this.fontSize * 0.2 }) {
            Text(this.t('学习模式', 'Learning Mode'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.95);
            Text(this.t(
              '表格仅显示首个非空列，其余内容用 * 隐藏，便于自测记忆',
              'Tables show only the first non-empty column, hiding rest with * for self-testing'
            ))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.75)
              .opacity(0.7);
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Toggle({ type: ToggleType.Switch, isOn: this.learningModeEnabled })
            .selectedColor(this.theme.accentColor)
            .onChange((isOn: boolean) => this.toggleLearningMode(isOn));
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });
      }
      .width('100%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

      // 在线 Markdown 链接管理
      Column({ space: 0 }) {
        Row() {
          Column({ space: this.fontSize * 0.2 }) {
            Text(this.t('添加在线 Markdown', 'Add Online Markdown'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.95);
            Text(this.t(
              '输入 MD 文件链接，解析后可在目录中查看',
              'Enter MD file link, parsed content will appear in catalog'
            ))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.75)
              .opacity(0.7);
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.5 });

        Row({ space: this.fontSize * 0.5 }) {
          TextInput({
            text: this.onlineMdInputUrl,
            placeholder: this.t('输入 Markdown URL...', 'Enter Markdown URL...'),
          })
            .layoutWeight(1)
            .fontSize(this.fontSize * 0.8)
            .placeholderFont({ size: this.fontSize * 0.8 })
            .fontColor(this.theme.titleColor)
            .placeholderColor(this.theme.mutedTextColor)
            .enableAutoFill(false)
            .backgroundColor(this.theme.pageBackgroundColor)
            .border({ width: 1, color: this.theme.borderColor })
            .borderRadius(this.fontSize * 0.5)
            .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
            .onChange((value: string) => {
              this.onlineMdInputUrl = value;
            });

          Text(this.onlineMdParsing ? this.t('解析中...', 'Parsing...') : this.t('添加', 'Add'))
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.onlineMdParsing ? this.theme.mutedTextColor : this.theme.chipSelectedTextColor)
            .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
            .backgroundColor(this.onlineMdParsing ? this.theme.chipBackgroundColor : this.theme.chipSelectedBackgroundColor)
            .borderRadius(this.fontSize * 66)
            .onClick(() => {
              if (!this.onlineMdParsing) {
                this.parseAndAddOnlineMd();
              }
            });
        }
        .width('100%')
        .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });

        if (this.onlineMdParseResult) {
          Text(this.onlineMdParseResult)
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.onlineMdParseResult.includes(this.t('成功', 'success')) ? this.theme.accentColor : this.theme.dangerTextColor)
            .width('100%')
            .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });
        }

        if (this.onlineMdLinks.length > 0) {
          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Column({ space: this.fontSize * 0.3 }) {
            Row({ space: this.fontSize * 0.5 }) {
              Text(this.t(`已添加 ${this.onlineMdLinks.length} 个链接`, `${this.onlineMdLinks.length} links added`))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.mutedTextColor);
              Text(this.t('（点击链接复制）', '(click link to copy)'))
                .fontSize(this.fontSize * 0.75)
                .fontColor(this.theme.mutedTextColor)
                .opacity(0.7);
              if (this.onlineMdCopySuccess) {
                Text(this.t('复制成功', 'Copied'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.accentColor)
                  .fontWeight(FontWeight.Medium);
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center);

            ForEach(this.onlineMdLinks, (link: OnlineMdLink) => {
              Row({ space: this.fontSize * 0.5 }) {
                Column({ space: this.fontSize * 0.1 }) {
                  Text(link.name)
                    .fontSize(this.fontSize * 0.9)
                    .fontColor(this.theme.titleColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                  Text(link.url)
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.accentColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .decoration({ type: TextDecorationType.Underline });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .onClick(() => this.copyOnlineMdUrl(link.url));

                if (this.isDefaultOnlineMdLink(link)) {
                  Text(this.t('删除', 'Delete'))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor)
                    .opacity(0.7)
                    .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 });
                } else {
                  Text(this.t('删除', 'Delete'))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.dangerTextColor)
                    .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 })
                    .onClick(() => this.removeOnlineMd(link.id));
                }
              }
              .width('100%')
              .padding({ top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 });
            }, (link: OnlineMdLink) => link.id);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.5, bottom: this.fontSize * 0.7 });
        }
      }
      .width('100%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(this.t('开源地址：', 'Open Source: '))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 0.9);
        Text('github.com/jqknono/reference-harmony')
          .fontColor(this.theme.accentColor)
          .fontSize(this.fontSize * 0.9)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => openExternalLink(this.getUIContext().getHostContext(), 'github.com/jqknono/reference-harmony'));
      }
      .width('100%')
      .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.1, color: this.theme.borderColor });

      Column({ space: this.fontSize * 0.2 }) {
        Text(this.t(`中文备忘清单：${this.formatDocCount(this.zhDocCount)}`, `ZH cheat sheets: ${this.formatDocCount(this.zhDocCount)}`))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 0.85);
        Text(this.t(`英文备忘清单：${this.formatDocCount(this.enDocCount)}`, `EN cheat sheets: ${this.formatDocCount(this.enDocCount)}`))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 0.85);
      }
      }
      .padding(this.tabPadding())
      .width('100%')
    }
    .align(Alignment.Top)
    .height('100%')
    .width('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  private getTabLabel(index: number): string {
    if (index === 0) return this.t('目录', 'Catalog');
    if (index === 1) return this.t('备忘清单', 'Cheatsheet');
    if (index === 2) return this.t('测验', 'Quiz');
    return this.t('设置', 'Settings');
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds}秒`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}分${remainingSeconds}秒`;
  }

  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hour = date.getHours();
    const minute = date.getMinutes();
    return `${month}/${day} ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
  }

  @Builder
  private QuizTab(): void {
    Column({ space: this.fontSize * 0.6 }) {
      Text(this.t('测验', 'Quiz'))
        .fontSize(this.fontSize * 1.47)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.titleColor)
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1 });

      if (this.quizMode === 'idle') {
        this.QuizIdleView();
      } else if (this.quizMode === 'selecting') {
        this.QuizSelectingView();
      } else if (this.quizMode === 'answering') {
        this.QuizAnsweringView();
      } else if (this.quizMode === 'result') {
        this.QuizResultView();
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  @Builder
  private QuizIdleView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      if (!this.selectedDoc) {
        Column({ space: this.fontSize * 0.5 }) {
          Text(this.t('请先选择文档', 'Please select a document first'))
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor);
          Text(this.t('在"目录"中打开一个文档后，即可开始测验', 'Open a document in "Catalog" to start quiz'))
            .fontSize(this.fontSize * 0.8)
            .fontColor(this.theme.mutedTextColor)
            .opacity(0.7);
        }
        .padding(this.fontSize * 1);
      } else {
        Column({ space: this.fontSize * 0.6 }) {
          Row({ space: this.fontSize * 0.5 }) {
            Text(this.t('当前文档：', 'Current Doc: '))
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor);
            Text(this.selectedDoc.name || this.selectedDoc.title)
              .fontSize(this.fontSize)
              .fontColor(this.theme.titleColor)
              .fontWeight(FontWeight.Medium);
          }
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          Text(this.t(`可生成 ${this.quizAvailableCount} 道题目`, `${this.quizAvailableCount} questions available`))
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          if (this.quizAvailableCount > 0) {
            Row({ space: this.fontSize * 0.6 }) {
              ForEach([5, 10, 15], (count: number) => {
                if (this.quizAvailableCount >= count || count === 5) {
                  Text(this.t(`${Math.min(count, this.quizAvailableCount)} 题`, `${Math.min(count, this.quizAvailableCount)} Q`))
                    .fontSize(this.fontSize * 0.9)
                    .fontColor(this.theme.accentColor)
                    .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.6, bottom: this.fontSize * 0.6 })
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .border({ width: 1, color: this.theme.accentColor })
                    .borderRadius(this.fontSize * 0.5)
                    .onClick(() => this.startQuiz(Math.min(count, this.quizAvailableCount)));
                }
              }, (count: number) => `quiz_start_${count}`);
            }
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5 });
          } else {
            Text(this.t('当前文档没有可生成测验的表格内容', 'No table content available for quiz in this document'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.dangerTextColor)
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
          }
        }
        .width('100%')
        .padding({ top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.5)
        .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });
      }

      // 测验记录
      if (this.quizRecord && this.quizRecord.totalQuizCount > 0) {
        Column({ space: this.fontSize * 0.5 }) {
          Text(this.t('测验记录', 'Quiz History'))
            .fontSize(this.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme.titleColor);

          Row({ space: this.fontSize * 1 }) {
            Column({ space: this.fontSize * 0.2 }) {
              Text(`${this.quizRecord.totalQuizCount}`)
                .fontSize(this.fontSize * 1.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.accentColor);
              Text(this.t('总测验', 'Total'))
                .fontSize(this.fontSize * 0.75)
                .fontColor(this.theme.mutedTextColor);
            }

            Column({ space: this.fontSize * 0.2 }) {
              Text(`${this.quizRecord.averageScore}%`)
                .fontSize(this.fontSize * 1.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.accentColor);
              Text(this.t('平均分', 'Average'))
                .fontSize(this.fontSize * 0.75)
                .fontColor(this.theme.mutedTextColor);
            }

            Column({ space: this.fontSize * 0.2 }) {
              Text(`${this.quizRecord.totalCorrectCount}/${this.quizRecord.totalQuestionCount}`)
                .fontSize(this.fontSize * 1.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.accentColor);
              Text(this.t('正确率', 'Correct'))
                .fontSize(this.fontSize * 0.75)
                .fontColor(this.theme.mutedTextColor);
            }
          }
          .justifyContent(FlexAlign.SpaceAround)
          .width('100%');
        }
        .width('100%')
        .padding(this.fontSize * 1)
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.5)
        .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });

        // 最近测验列表
        if (this.quizRecord.sessions.length > 0) {
          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('最近测验', 'Recent Quizzes'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor)
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

            List() {
              ForEach(this.quizRepository.getRecentSessions(this.quizRecord, 10), (session: QuizSession) => {
                ListItem() {
                  Row() {
                    Column({ space: this.fontSize * 0.15 }) {
                      Text(session.docName || session.docTitle)
                        .fontSize(this.fontSize * 0.9)
                        .fontColor(this.theme.titleColor)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis });
                      Text(this.formatDateTime(session.endTime))
                        .fontSize(this.fontSize * 0.75)
                        .fontColor(this.theme.mutedTextColor);
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start);

                    Column({ space: this.fontSize * 0.1 }) {
                      Text(`${session.score}%`)
                        .fontSize(this.fontSize)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(session.score >= 60 ? this.theme.accentColor : this.theme.dangerTextColor);
                      Text(`${session.correctCount}/${session.totalCount}`)
                        .fontSize(this.fontSize * 0.75)
                        .fontColor(this.theme.mutedTextColor);
                    }
                    .alignItems(HorizontalAlign.End);
                  }
                  .width('100%')
                  .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
                }
              }, (session: QuizSession) => session.id);
            }
            .layoutWeight(1)
            .divider({ strokeWidth: 1, color: this.theme.borderColor, startMargin: this.fontSize * 1, endMargin: this.fontSize * 1 });
          }
          .layoutWeight(1);
        }
      }
    }
    .layoutWeight(1);
  }

  @Builder
  private QuizSelectingView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Text(this.t('选择题目数量', 'Select Question Count'))
        .fontSize(this.fontSize)
        .fontColor(this.theme.titleColor);
    }
    .padding(this.fontSize * 1);
  }

  @Builder
  private QuizAnsweringView(): void {
    Column({ space: this.fontSize * 0.6 }) {
      // 进度条
      Row() {
        Text(`${this.quizCurrentIndex + 1} / ${this.quizQuestions.length}`)
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.mutedTextColor);
        Blank();
        Text(this.t('退出', 'Exit'))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.dangerTextColor)
          .onClick(() => this.resetQuiz());
      }
      .width('100%')
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

      Progress({ value: this.quizCurrentIndex + 1, total: this.quizQuestions.length })
        .width('100%')
        .color(this.theme.accentColor)
        .backgroundColor(this.theme.surfaceMutedBackgroundColor)
        .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });

      // 题目
      Scroll() {
        Column({ space: this.fontSize * 0.8 }) {
          Text(this.quizQuestions[this.quizCurrentIndex]?.question ?? '')
            .fontSize(this.fontSize * 1.1)
            .fontColor(this.theme.titleColor)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          // 选项
          Column({ space: this.fontSize * 0.5 }) {
            ForEach(this.quizQuestions[this.quizCurrentIndex]?.options ?? [], (option: QuizOption, optionIndex: number) => {
              Row({ space: this.fontSize * 0.6 }) {
                Text(String.fromCharCode(65 + optionIndex))
                  .fontSize(this.fontSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getOptionLabelColor(optionIndex));

                Text(option.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.getOptionTextColor(optionIndex))
                  .layoutWeight(1);

                if (this.quizShowAnswer) {
                  if (option.isCorrect) {
                    Text('✓')
                      .fontSize(this.fontSize)
                      .fontColor(0xff4caf50);
                  } else if (optionIndex === this.quizSelectedOptionIndex && !option.isCorrect) {
                    Text('✗')
                      .fontSize(this.fontSize)
                      .fontColor(this.theme.dangerTextColor);
                  }
                }
              }
              .width('100%')
              .padding(this.fontSize * 0.8)
              .backgroundColor(this.getOptionBackgroundColor(optionIndex))
              .border({ width: this.fontSize * 0.1, color: this.getOptionBorderColor(optionIndex) })
              .borderRadius(this.fontSize * 0.5)
              .onClick(() => this.selectQuizOption(optionIndex));
            }, (_option: QuizOption, optionIndex: number) => {
              const qid = this.quizQuestions[this.quizCurrentIndex]?.id ?? 'q';
              return `${qid}_option_${optionIndex}`;
            });
          }
          .width('100%')
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          // 解释（答案后显示）
          if (this.quizShowAnswer && this.quizQuestions[this.quizCurrentIndex]?.explanation) {
            Text(this.quizQuestions[this.quizCurrentIndex].explanation)
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor)
              .fontStyle(FontStyle.Italic)
              .width('100%')
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
          }
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);

      // 底部按钮
      Row({ space: this.fontSize * 1 }) {
        if (!this.quizShowAnswer) {
          Text(this.t('确认答案', 'Confirm'))
            .fontSize(this.fontSize)
            .fontColor(this.quizSelectedOptionIndex >= 0 ? 0xffffffff : this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.quizSelectedOptionIndex >= 0 ? this.theme.accentColor : this.theme.surfaceMutedBackgroundColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.confirmQuizAnswer());
        } else {
          Text(this.quizCurrentIndex + 1 >= this.quizQuestions.length ? this.t('查看结果', 'View Results') : this.t('下一题', 'Next'))
            .fontSize(this.fontSize)
            .fontColor(0xffffffff)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.nextQuizQuestion());
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, bottom: this.fontSize * 1 });
    }
    .layoutWeight(1)
    .width('100%');
  }

  private getOptionLabelColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.accentColor : this.theme.mutedTextColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex) return this.theme.dangerTextColor;
    return this.theme.mutedTextColor;
  }

  private getOptionTextColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.titleColor : this.theme.textColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex) return this.theme.dangerTextColor;
    return this.theme.textColor;
  }

  private getOptionBackgroundColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.chipSelectedBackgroundColor : this.theme.surfaceBackgroundColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0x204caf50;
    if (optionIndex === this.quizSelectedOptionIndex && !option?.isCorrect) return 0x20f44336;
    return this.theme.surfaceBackgroundColor;
  }

  private getOptionBorderColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.accentColor : this.theme.borderColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex && !option?.isCorrect) return this.theme.dangerTextColor;
    return this.theme.borderColor;
  }

  private getQuizCorrectCount(): number {
    let count = 0;
    for (let i = 0; i < this.quizAnswers.length; i++) {
      if (this.quizAnswers[i].isCorrect) count++;
    }
    return count;
  }

  private getQuizScore(): number {
    return calculateScore(this.getQuizCorrectCount(), this.quizQuestions.length);
  }

  @Builder
  private QuizResultView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      // 分数显示
      Column({ space: this.fontSize * 0.3 }) {
        Text(this.t('测验完成！', 'Quiz Complete!'))
          .fontSize(this.fontSize * 1.2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleColor);

        Text(`${this.getQuizScore()}%`)
          .fontSize(this.fontSize * 3)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getQuizScore() >= 60 ? this.theme.accentColor : this.theme.dangerTextColor);

        Text(this.t(`${this.getQuizCorrectCount()} / ${this.quizQuestions.length} 正确`, `${this.getQuizCorrectCount()} / ${this.quizQuestions.length} Correct`))
          .fontSize(this.fontSize)
          .fontColor(this.theme.mutedTextColor);

        Text(this.t(`用时：${this.formatDuration(Date.now() - this.quizStartTime)}`, `Duration: ${this.formatDuration(Date.now() - this.quizStartTime)}`))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.mutedTextColor);
      }
      .width('100%')
      .padding(this.fontSize * 1.5)
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.5)
      .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });

      // 答题详情
      Text(this.t('答题详情', 'Answer Details'))
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.titleColor)
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

      List() {
        ForEach(this.quizQuestions, (question: QuizQuestion, qIndex: number) => {
          ListItem() {
            Row({ space: this.fontSize * 0.5 }) {
              Text(`${qIndex + 1}.`)
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.mutedTextColor);

              Text(question.question)
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.textColor)
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              Text(this.quizAnswers[qIndex]?.isCorrect ? '✓' : '✗')
                .fontSize(this.fontSize)
                .fontColor(this.quizAnswers[qIndex]?.isCorrect ? 0xff4caf50 : this.theme.dangerTextColor);
            }
            .width('100%')
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
          }
        }, (question: QuizQuestion, qIndex: number) => `result_${qIndex}`);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: this.theme.borderColor, startMargin: this.fontSize * 1, endMargin: this.fontSize * 1 });

      // 底部按钮
      Row({ space: this.fontSize * 1 }) {
        Text(this.t('返回', 'Back'))
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .border({ width: 1, color: this.theme.accentColor })
          .borderRadius(this.fontSize * 0.5)
          .onClick(() => this.resetQuiz());

        if (this.quizAvailableCount > 0) {
          Text(this.t('再来一次', 'Try Again'))
            .fontSize(this.fontSize)
            .fontColor(0xffffffff)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.startQuiz(Math.min(this.quizQuestions.length, this.quizAvailableCount)));
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, bottom: this.fontSize * 1 });
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  private TabBarItem(index: number): void {
    Column() {
      Text(this.getTabLabel(index))
        .fontSize(this.fontSize * 1)
        .fontColor(this.currentTabIndex === index ? this.theme.accentColor : this.theme.mutedTextColor)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal);
    }
    .padding({ top: this.fontSize * 0.2, bottom: this.fontSize * 0, left: this.fontSize * 1, right: this.fontSize * 1 });
  }

  @Builder
  private CurrentTabContent(): void {
    if (this.currentTabIndex === 0) {
      this.DocListTab();
    } else if (this.currentTabIndex === 1) {
      this.ReadTab();
    } else if (this.currentTabIndex === 2) {
      this.QuizTab();
    } else {
      this.SettingsTab();
    }
  }

  build() {
    Stack() {
      if (this.isLandscape) {
        this.CurrentTabContent();
      } else {
        Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex, controller: this.tabsController }) {
          TabContent() {
            this.DocListTab();
          }
          .tabBar(this.TabBarItem(0));

          TabContent() {
            this.ReadTab();
          }
          .tabBar(this.TabBarItem(1));

          TabContent() {
            this.QuizTab();
          }
          .tabBar(this.TabBarItem(2));

          TabContent() {
            this.SettingsTab();
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
        this.TocPanel();
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
