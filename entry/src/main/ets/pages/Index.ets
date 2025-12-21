import preferences from '@ohos.data.preferences';
import { window } from '@kit.ArkUI';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeId, AppThemeTokens } from '../common/appTheme';
import { decodeIfEncoded } from '../common/encodedContent';
import { ReferenceCard } from '../components/ReferenceCard';
import { openExternalLink } from '../common/openExternalLink';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

interface SectionWithCards {
  section: ReferenceSection;
  cards: Array<ReferenceCardData>;
}

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

  private tabsController: TabsController = new TabsController();
  private listScroller: ListScroller = new ListScroller();
  private sectionNavScroller: Scroller = new Scroller();
  private listSearchScroller: ListScroller = new ListScroller();
  private listSectionNavScroller: Scroller = new Scroller();
  private listCardNavScroller: Scroller = new Scroller();
  private repository: ReferenceRepository | undefined = undefined;
  private openDocRequestId: number = 0;
  @State private fontSize: number = 15;
  @State private orientationMode: 'portrait' | 'landscape' | 'auto' = 'portrait';
  @State private isLandscape: boolean = false;

  private lengthToNumber(value: Length): number {
    if (typeof value === 'number') return value;
    const parsed: number = Number.parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : 0;
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

  private applySystemBarTheme(): void {
    const host = this.getUIContext().getHostContext();
    if (!host) return;

    const backgroundColor: string = this.toHexColorString(this.theme.pageBackgroundColor);
    const lightIcon: boolean = this.themeId === 'dark';
    const properties: window.SystemBarProperties = {
      statusBarColor: backgroundColor,
      navigationBarColor: backgroundColor,
      isStatusBarLightIcon: lightIcon,
      isNavigationBarLightIcon: lightIcon,
    };

    Promise.resolve()
      .then((): Promise<window.Window> => window.getLastWindow(host))
      .then(
        (w: window.Window): void => {
          w.setWindowSystemBarProperties(properties).then(
            (): void => undefined,
            (): void => undefined,
          );
          Promise.resolve()
            .then((): void => w.setWindowBackgroundColor(backgroundColor))
            .then(
              (): void => undefined,
              (): void => undefined,
            );
        },
        (): void => undefined,
      );
  }

  private updateLandscapeFromArea(area: Area): void {
    const width: number = this.lengthToNumber(area.width);
    const height: number = this.lengthToNumber(area.height);
    const next: boolean = height > 0 && width > height;
    if (this.isLandscape !== next) {
      this.isLandscape = next;
      this.applySystemBarTheme();
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
    for (let i = 0; i < this.docs.length; i++) {
      const doc = this.docs[i];
      const haystack = [doc.name ?? '', doc.title ?? '', doc.id].join(' ').toLowerCase();
      if (haystack.indexOf(query) >= 0) {
        results.push(doc);
      }
    }
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
        this.listScroller.scrollToIndex(0);
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
    this.applySystemBarTheme();
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
    this.applySystemBarTheme();
    await this.loadLangSetting();
    await this.loadOrientationModeSetting();
    this.applyOrientationModeSetting(this.orientationMode);
    await this.loadManifest();
    await this.loadManifestCounts();
  }

  onBackPress(): boolean {
    if (this.showTocPanel) {
      this.showTocPanel = false;
      return true;
    }
    if (this.currentTabIndex !== 0) {
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
        })
          .layoutWeight(1)
          .fontSize(this.fontSize)
          .fontColor(this.theme.titleColor)
          .placeholderColor(this.theme.mutedTextColor)
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
        ForEach(this.catalogSearchQuery.trim() ? this.catalogSearchResults : this.docs, (doc: ReferenceDocSummary) => {
          ListItem() {
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

              Text(this.t('打开', 'Open')).fontSize(this.fontSize * 0.8).fontColor(this.theme.accentColor);
            }
            .padding(this.fontSize * 1)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.8)
            .onClick(() => this.openDoc(doc.id, true));
          }
          .margin({ bottom: this.fontSize * 0.6 });
        }, (doc: ReferenceDocSummary) => `${this.lang}:${doc.id}`);
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
            this.showTocPanel = true;
          });
      }
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.4 });

      if (this.selectedDoc && !this.isLandscape) {
        Row({ space: this.fontSize * 0.6 }) {
          TextInput({
            text: this.searchQuery,
            placeholder: this.t('搜索当前文档…', 'Search current doc…'),
          })
            .layoutWeight(1)
            .fontSize(this.fontSize * 1)
            .fontColor(this.theme.titleColor)
            .placeholderColor(this.theme.mutedTextColor)
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
                  ReferenceCard({ card, lang: this.lang, theme: this.theme, fontSize: this.fontSize, unboundedTableColumns: this.isLandscape })
                    .margin({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:search:${card.id}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:search:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0 });

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
                  ReferenceCard({ card, lang: this.lang, theme: this.theme, fontSize: this.fontSize, unboundedTableColumns: this.isLandscape })
                    .margin({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:${card.id}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0 });
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
                      this.showTocPanel = false;
                      this.searchQuery = '';
                      this.listScroller.scrollToItemInGroup(groupIndex, cardIndex + 1, true, ScrollAlign.START);
                    });
                }
              }, (card: ReferenceCardData) => `toc:${this.selectedDocId}:${card.id}`);
            }
          }, (group: SectionWithCards) => `toc:${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0 });
      }
      .width('100%')
      .height('70%')
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius({ topLeft: this.fontSize * 1, topRight: this.fontSize * 1 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.showTocPanel = false;
    });
  }

  @Builder
  private SettingsTab(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Text(this.t('设置', 'Settings')).fontSize(this.fontSize * 1.47).fontWeight(FontWeight.Bold).fontColor(this.theme.titleColor);

      Column({ space: 0 }) {
        Row() {
          Text(this.t('屏幕方向', 'Orientation'))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 1);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('竖屏', 'Portrait'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchOrientationMode('portrait'));
            Text(this.t('横屏', 'Landscape'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchOrientationMode('landscape'));
            Text(this.t('自动', 'Auto'))
              .fontSize(this.fontSize * 0.8)
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
            .fontSize(this.fontSize * 1);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('中文', '中文'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.lang === 'zh' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.lang === 'zh' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchLang('zh'));
            Text('English')
              .fontSize(this.fontSize * 0.8)
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
            .fontSize(this.fontSize * 1);

          Row({ space: this.fontSize * 0.6 }) {
            Text(this.t('暗黑', 'Dark'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.themeId === 'dark' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.themeId === 'dark' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => this.switchTheme('dark'));
            Text(this.t('明亮', 'Light'))
              .fontSize(this.fontSize * 0.8)
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

      Row() {
        Text(this.t('开源地址：', 'Open Source: '))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 1);
        Text('github.com/jqknono/reference-harmony')
          .fontColor(this.theme.accentColor)
          .fontSize(this.fontSize * 1)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => openExternalLink(this.getUIContext().getHostContext(), 'github.com/jqknono/reference-harmony'));
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.8)
      .border({ width: this.fontSize * 0.1, color: this.theme.borderColor });

      Column({ space: this.fontSize * 0.2 }) {
        Text(this.t(`中文备忘清单：${this.formatDocCount(this.zhDocCount)}`, `ZH cheat sheets: ${this.formatDocCount(this.zhDocCount)}`))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 1);
        Text(this.t(`英文备忘清单：${this.formatDocCount(this.enDocCount)}`, `EN cheat sheets: ${this.formatDocCount(this.enDocCount)}`))
          .fontColor(this.theme.mutedTextColor)
          .fontSize(this.fontSize * 1);
      }
    }
    .padding(this.tabPadding())
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  private getTabLabel(index: number): string {
    if (index === 0) return this.t('目录', 'Catalog');
    if (index === 1) return this.t('备忘清单', 'Cheatsheet');
    return this.t('设置', 'Settings');
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
            this.SettingsTab();
          }
          .tabBar(this.TabBarItem(2));
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
