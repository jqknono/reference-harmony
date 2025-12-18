import preferences from '@ohos.data.preferences';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeId, AppThemeTokens } from '../common/appTheme';
import { decodeIfEncoded } from '../common/encodedContent';
import { ReferenceCard } from '../components/ReferenceCard';

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
  @State private selectedDoc: ReferenceDoc | undefined = undefined;
  @State private selectedDocId: string = '';
  @State private sectionCards: Array<SectionWithCards> = [];
  @State private searchQuery: string = '';
  @State private searchSectionCards: Array<SectionWithCards> = [];
  @State private searchResultCount: number = 0;
  @State private iconErrorKeys: Array<string> = [];

  private tabsController: TabsController = new TabsController();
  private listScroller: ListScroller = new ListScroller();
  private sectionNavScroller: Scroller = new Scroller();
  private repository: ReferenceRepository | undefined = undefined;

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private iconKey(docId: string, icon: string | undefined): string {
    return icon ? `${docId}:${icon}` : docId;
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
    if (icon && !this.hasIconError(this.iconKey(docId, icon))) {
      Image(icon)
        .width(size)
        .height(size)
        .borderRadius(radius)
        .backgroundColor(this.theme.avatarBackgroundColor)
        .onError(() => this.markIconError(this.iconKey(docId, icon)));
    } else {
      Text(this.getAvatarText(label))
        .width(size)
        .height(size)
        .textAlign(TextAlign.Center)
        .fontSize(Math.floor(size * 0.42))
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
      let list: Array<ReferenceCardData> | undefined = bySection.get(card.sectionId);
      if (!list) {
        list = new Array<ReferenceCardData>();
        bySection.set(card.sectionId, list);
      }
      list.push(card);
    }

    let sections: Array<ReferenceSection> = doc.sections;
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
    const encoded = card.encoded;
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
      if (!this.cardMatchesTokens(card, tokens)) continue;
      matchedCount++;
      let list = bySection.get(card.sectionId);
      if (!list) {
        list = new Array<ReferenceCardData>();
        bySection.set(card.sectionId, list);
      }
      list.push(card);
    }

    let sections: Array<ReferenceSection> = doc.sections;
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
  }

  private async openDoc(docId: string, switchToReadTab: boolean = true): Promise<void> {
    const repo = await this.ensureRepository();
    if (!repo) {
      return;
    }

    this.loading = true;
    this.errorText = '';
    await repo.getDocByLang(this.lang, docId).then(
      (doc: ReferenceDoc): void => {
        this.selectedDoc = doc;
        this.selectedDocId = docId;
        this.rebuildSectionCards(doc);
        this.rebuildSearchResults();
        if (switchToReadTab) {
          this.tabsController.changeIndex(1);
        }
      },
      (e: Error | string): void => {
        this.errorText = this.t(`加载文档失败：${String(e)}`, `Failed to load doc: ${String(e)}`);
      },
    );
    this.loading = false;
  }

  private async switchLang(next: ReferenceLang): Promise<void> {
    if (this.lang === next) return;
    this.lang = next;
    await this.saveLangSetting(next);
    this.selectedDoc = undefined;
    this.selectedDocId = '';
    this.sectionCards = [];
    this.searchQuery = '';
    this.searchSectionCards = [];
    this.searchResultCount = 0;
    await this.loadManifest(false);
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

    this.loading = true;
    this.errorText = '';
      await repo.getManifestByLang(this.lang).then(
        async (manifest: ReferenceManifest): Promise<void> => {
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
        this.errorText = this.t(
          `加载 manifest 失败：${String(e)}\n\n请先运行 tools/sync_reference_docs.mjs 生成 rawfile 数据。`,
          `Failed to load manifest: ${String(e)}\n\nRun tools/sync_reference_docs.mjs to generate rawfile data.`,
        );
      },
    );
    this.loading = false;
  }

  async aboutToAppear(): Promise<void> {
    await this.loadThemeSetting();
    await this.loadLangSetting();
    await this.loadManifest();
  }

  @Builder
  private DocListTab(): void {
    Column({ space: 10 }) {
      Text(this.t('快速参考', 'Quick Reference'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.titleColor);

      if (this.loading) {
        Text(this.t('加载中…', 'Loading…')).fontColor(this.theme.mutedTextColor);
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(this.theme.dangerTextColor).maxLines(6);
      }

      List() {
        ForEach(this.docs, (doc: ReferenceDocSummary) => {
          ListItem() {
            Row({ space: 12 }) {
              this.DocAvatar(doc.id, doc.name || doc.id, doc.icon, 34, 10);

              Column({ space: 4 }) {
                Text(doc.name || doc.id).fontSize(16).fontColor(this.theme.titleColor);

                if (doc.title && doc.title !== doc.name) {
                  Text(doc.title)
                    .fontSize(12)
                    .fontColor(this.theme.mutedTextColor)
                    .maxLines(2);
                }

                Text(this.t(`${doc.sectionCount} 章节 · ${doc.cardCount} 卡片`, `${doc.sectionCount} sections · ${doc.cardCount} cards`))
                  .fontSize(12)
                  .fontColor(this.theme.mutedTextColor);
              }.layoutWeight(1);

              Text(this.t('打开', 'Open')).fontSize(12).fontColor(this.theme.accentColor);
            }
            .padding(14)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(12)
            .onClick(() => this.openDoc(doc.id, true));
          }
          .margin({ bottom: 10 });
        }, (doc: ReferenceDocSummary) => doc.id);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 });
    }
    .padding(16)
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  @Builder
  private ReadTab(): void {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (this.selectedDoc) {
          this.DocAvatar(
            this.selectedDocId,
            this.selectedDoc.name || this.selectedDoc.title || this.selectedDocId,
            this.selectedDoc.icon,
            28,
            8,
          );
        }

        Column({ space: 2 }) {
          Text(this.selectedDoc ? (this.selectedDoc.name || this.selectedDoc.title) : this.t('未选择', 'No selection'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.titleColor);

          if (this.selectedDoc && this.selectedDoc.title && this.selectedDoc.title !== this.selectedDoc.name) {
            Text(this.selectedDoc.title).fontSize(12).fontColor(this.theme.mutedTextColor).maxLines(2);
          }
        }
        .layoutWeight(1);

        if (this.selectedDocId) {
          Text(this.selectedDocId).fontSize(12).fontColor(this.theme.mutedTextColor);
        }
      }
      .padding({ left: 16, right: 16, top: 14, bottom: 6 });

      if (this.loading) {
        Text(this.t('加载中…', 'Loading…')).fontColor(this.theme.mutedTextColor).padding({ left: 16, right: 16 });
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(this.theme.dangerTextColor).padding({ left: 16, right: 16 }).maxLines(6);
      }

      List({ scroller: this.listScroller }) {
        ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
          ListItemGroup() {
            ListItem() {
              Text(group.section.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textColor)
                .padding({ left: 16, right: 16, top: 12, bottom: 4 });
            }

            ForEach(group.cards, (card: ReferenceCardData) => {
              ListItem() {
                ReferenceCard({ card, lang: this.lang, theme: this.theme })
                  .margin({ left: 16, right: 16, top: 8, bottom: 8 });
              }
            }, (card: ReferenceCardData) => `${this.selectedDocId}:${card.id}`);
          }
        }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 });

      if (this.sectionCards.length > 0) {
        Scroll(this.sectionNavScroller) {
          Row({ space: 8 }) {
            ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
              Text(group.section.title)
                .fontSize(12)
                .fontColor(this.theme.chipTextColor)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor(this.theme.chipBackgroundColor)
                .borderRadius(999)
                .onClick(() => this.listScroller.scrollToItemInGroup(groupIndex, 0, true, ScrollAlign.START));
            }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 });
        }
        .backgroundColor(this.theme.surfaceMutedBackgroundColor)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off);
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  @Builder
  private SearchTab(): void {
    Column({ space: 10 }) {
      Text(this.t('搜索', 'Search')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.theme.titleColor);

      if (!this.selectedDocId || !this.selectedDoc) {
        Text(this.t('请先在“文档”中打开一个文档', 'Open a doc in “Docs” first.')).fontColor(this.theme.mutedTextColor);
      } else {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(this.t('当前文档', 'Current doc')).fontSize(12).fontColor(this.theme.mutedTextColor);
            Text(this.selectedDoc.name || this.selectedDoc.title || this.selectedDocId)
              .fontSize(14)
              .fontColor(this.theme.titleColor)
              .maxLines(2);
          }.layoutWeight(1);

          Text(this.t('切换', 'Change'))
            .fontSize(12)
            .fontColor(this.theme.accentColor)
            .onClick(() => this.tabsController.changeIndex(0));
        }

        Row({ space: 10 }) {
          TextInput({
            text: this.searchQuery,
            placeholder: this.t('按标题/内容搜索…', 'Search title/body…'),
          })
            .layoutWeight(1)
            .fontSize(15)
            .fontColor(this.theme.titleColor)
            .placeholderColor(this.theme.mutedTextColor)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .border({ width: 1, color: this.theme.borderColor })
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onChange((value: string) => {
              this.searchQuery = value;
              this.rebuildSearchResults();
            });

          if (this.searchQuery.trim()) {
            Text(this.t('清除', 'Clear'))
              .fontSize(12)
              .fontColor(this.theme.mutedTextColor)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .border({ width: 1, color: this.theme.borderColor })
              .borderRadius(12)
              .onClick(() => {
                this.searchQuery = '';
                this.rebuildSearchResults();
              });
          }
        }

        if (!this.searchQuery.trim()) {
          Text(this.t('输入关键词开始搜索（当前仅搜索已打开的文档）', 'Type to search (current doc only).'))
            .fontColor(this.theme.mutedTextColor);
        } else {
          Text(this.t(`${this.searchResultCount} 条结果`, `${this.searchResultCount} results`)).fontColor(this.theme.mutedTextColor);
        }

        if (this.searchQuery.trim() && this.searchResultCount === 0) {
          Text(this.t('没有匹配结果', 'No results.')).fontColor(this.theme.mutedTextColor);
        }

        if (this.searchResultCount > 0) {
          List() {
            ForEach(this.searchSectionCards, (group: SectionWithCards) => {
              ListItemGroup() {
                ListItem() {
                  Text(`${group.section.title} (${group.cards.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.textColor)
                    .padding({ left: 16, right: 16, top: 12, bottom: 4 });
                }

                ForEach(group.cards, (card: ReferenceCardData) => {
                  ListItem() {
                    ReferenceCard({ card, lang: this.lang, theme: this.theme })
                      .margin({ left: 16, right: 16, top: 8, bottom: 8 });
                  }
                }, (card: ReferenceCardData) => `${this.selectedDocId}:${card.id}`);
              }
            }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
          }
          .layoutWeight(1)
          .divider({ strokeWidth: 0 });
        }
      }
    }
    .padding(16)
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  @Builder
  private SettingsTab(): void {
    Column({ space: 10 }) {
      Text(this.t('设置', 'Settings')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.theme.titleColor);

      Row({ space: 10 }) {
        Text(this.t('语言', 'Language')).fontColor(this.theme.mutedTextColor);
        Text(this.t('中文', '中文'))
          .fontSize(12)
          .fontColor(this.lang === 'zh' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.lang === 'zh' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchLang('zh'));
        Text('English')
          .fontSize(12)
          .fontColor(this.lang === 'en' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.lang === 'en' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchLang('en'));
      }

      Row({ space: 10 }) {
        Text(this.t('主题', 'Theme')).fontColor(this.theme.mutedTextColor);
        Text(this.t('暗黑', 'Dark'))
          .fontSize(12)
          .fontColor(this.themeId === 'dark' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.themeId === 'dark' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchTheme('dark'));
        Text(this.t('明亮', 'Light'))
          .fontSize(12)
          .fontColor(this.themeId === 'light' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.themeId === 'light' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchTheme('light'));
      }

      Text(this.t('中文数据源：jaywcjlove/reference/docs', 'ZH source: jaywcjlove/reference/docs')).fontColor(this.theme.mutedTextColor);
      Text(this.t('英文数据源：Fechin/reference/source/_posts', 'EN source: Fechin/reference/source/_posts')).fontColor(this.theme.mutedTextColor);
      Text(this.t('同步脚本：tools/sync_reference_docs.mjs', 'Sync script: tools/sync_reference_docs.mjs')).fontColor(this.theme.mutedTextColor);
    }
    .padding(16)
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex, controller: this.tabsController }) {
      TabContent() {
        this.DocListTab();
      }
      .tabBar(this.t('文档', 'Docs'));

      TabContent() {
        this.ReadTab();
      }
      .tabBar(this.t('阅读', 'Read'));

      TabContent() {
        this.SearchTab();
      }
      .tabBar(this.t('搜索', 'Search'));

      TabContent() {
        this.SettingsTab();
      }
      .tabBar(this.t('设置', 'Settings'));
    }
    .onChange((index: number) => {
      this.currentTabIndex = index;
    });
  }
}
