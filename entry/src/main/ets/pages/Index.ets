import preferences from '@ohos.data.preferences';
import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceLang, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { getAppThemeTokens } from '../common/appTheme';
import type { AppThemeId, AppThemeTokens } from '../common/appTheme';
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
  @State private themeId: AppThemeId = 'reference';
  @State private theme: AppThemeTokens = getAppThemeTokens('reference');

  @State private docs: Array<ReferenceDocSummary> = [];
  @State private selectedDoc: ReferenceDoc | undefined = undefined;
  @State private selectedDocId: string = '';
  @State private sectionCards: Array<SectionWithCards> = [];

  private tabsController: TabsController = new TabsController();
  private listScroller: ListScroller = new ListScroller();
  private sectionNavScroller: Scroller = new Scroller();
  private repository: ReferenceRepository | undefined = undefined;

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
      this.themeId = 'reference';
      this.theme = getAppThemeTokens(this.themeId);
      return;
    }
    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get('theme', 'reference'))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : String(value)),
        (): string => 'reference',
      );
    this.themeId = saved === 'coo' ? 'coo' : 'reference';
    this.theme = getAppThemeTokens(this.themeId);
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

  private async openDoc(docId: string): Promise<void> {
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
        this.tabsController.changeIndex(1);
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
          await this.openDoc(this.docs[0].id);
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
              if (doc.icon) {
                Image(doc.icon)
                  .width(34)
                  .height(34)
                  .borderRadius(10)
                  .backgroundColor(this.theme.avatarBackgroundColor);
              } else {
                Text((doc.name || doc.id).slice(0, 1).toUpperCase())
                  .width(34)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .fontSize(14)
                  .fontColor(this.theme.avatarTextColor)
                  .backgroundColor(this.theme.avatarBackgroundColor)
                  .borderRadius(10);
              }

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
            .onClick(() => this.openDoc(doc.id));
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
        if (this.selectedDoc?.icon) {
          Image(this.selectedDoc.icon)
            .width(28)
            .height(28)
            .borderRadius(8)
            .backgroundColor(this.theme.avatarBackgroundColor);
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
      Text(this.t('TODO：搜索（按标题/内容过滤卡片）', 'TODO: Search (filter cards by title/body)')).fontColor(this.theme.mutedTextColor);
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
        Text('Reference')
          .fontSize(12)
          .fontColor(this.themeId === 'reference' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.themeId === 'reference' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchTheme('reference'));
        Text('Coo')
          .fontSize(12)
          .fontColor(this.themeId === 'coo' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.themeId === 'coo' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
          .borderRadius(999)
          .onClick(() => this.switchTheme('coo'));
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
