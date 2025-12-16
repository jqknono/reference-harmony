import { ReferenceRepository } from '../common/referenceRepository';
import type { ReferenceCardData, ReferenceDoc, ReferenceDocSummary, ReferenceManifest, ReferenceSection } from '../common/referenceModels';
import { ReferenceCard } from '../components/ReferenceCard';

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

  @State private docs: Array<ReferenceDocSummary> = [];
  @State private selectedDoc: ReferenceDoc | undefined = undefined;
  @State private selectedDocId: string = '';
  @State private sectionCards: Array<SectionWithCards> = [];

  private tabsController: TabsController = new TabsController();
  private listScroller: ListScroller = new ListScroller();
  private sectionNavScroller: Scroller = new Scroller();
  private repository: ReferenceRepository | undefined = undefined;

  private async ensureRepository(): Promise<ReferenceRepository | undefined> {
    if (this.repository) {
      return this.repository;
    }
    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.errorText = '无法获取 HostContext';
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
      const defaultSection: ReferenceSection = { id: 'default', title: '内容', startIndex: 0 };
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
    try {
      const doc: ReferenceDoc = await repo.getDoc(docId);
      this.selectedDoc = doc;
      this.selectedDocId = docId;
      this.rebuildSectionCards(doc);
      this.tabsController.changeIndex(1);
    } catch (e) {
      this.errorText = `加载文档失败：${String(e)}`;
    } finally {
      this.loading = false;
    }
  }

  private async loadManifest(): Promise<void> {
    const repo = await this.ensureRepository();
    if (!repo) {
      return;
    }

    this.loading = true;
    this.errorText = '';
    try {
      const manifest: ReferenceManifest = await repo.getManifest();
      this.docs = manifest.docs ?? [];
      if (!this.selectedDocId && this.docs.length > 0) {
        await this.openDoc(this.docs[0].id);
      }
    } catch (e) {
      this.errorText = `加载 manifest 失败：${String(e)}\n\n请先运行 tools/sync_reference_docs.mjs 生成 rawfile 数据。`;
    } finally {
      this.loading = false;
    }
  }

  async aboutToAppear(): Promise<void> {
    await this.loadManifest();
  }

  @Builder
  private DocListTab(): void {
    Column({ space: 10 }) {
      Text('快速参考')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(0x0f172a);

      if (this.loading) {
        Text('加载中…').fontColor(0x64748b);
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(0xb91c1c).maxLines(6);
      }

      List() {
        ForEach(this.docs, (doc: ReferenceDocSummary) => {
          ListItem() {
            Row() {
              Column({ space: 4 }) {
                Text(doc.title).fontSize(16).fontColor(0x0f172a);
                Text(`${doc.sectionCount} 章节 · ${doc.cardCount} 卡片`)
                  .fontSize(12)
                  .fontColor(0x64748b);
              }.layoutWeight(1);

              Text('打开').fontSize(12).fontColor(0x2563eb);
            }
            .padding(14)
            .backgroundColor(0xffffff)
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
    .backgroundColor(0xf1f5f9);
  }

  @Builder
  private ReadTab(): void {
    Column({ space: 10 }) {
      Row() {
        Text(this.selectedDoc ? this.selectedDoc.title : '阅读')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(0x0f172a)
          .layoutWeight(1);

        if (this.selectedDocId) {
          Text(this.selectedDocId).fontSize(12).fontColor(0x64748b);
        }
      }
      .padding({ left: 16, right: 16, top: 14, bottom: 6 });

      if (this.loading) {
        Text('加载中…').fontColor(0x64748b).padding({ left: 16, right: 16 });
      }

      if (this.errorText) {
        Text(this.errorText).fontColor(0xb91c1c).padding({ left: 16, right: 16 }).maxLines(6);
      }

      List({ scroller: this.listScroller }) {
        ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
          ListItemGroup() {
            ListItem() {
              Text(group.section.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(0x334155)
                .padding({ left: 16, right: 16, top: 12, bottom: 4 });
            }

            ForEach(group.cards, (card: ReferenceCardData) => {
              ListItem() {
                ReferenceCard({ card })
                  .margin({ left: 16, right: 16, top: 8, bottom: 8 });
              }
            }, (card: ReferenceCardData) => card.id);
          }
        }, (group: SectionWithCards) => group.section.id);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 });

      if (this.sectionCards.length > 0) {
        Scroll(this.sectionNavScroller) {
          Row({ space: 8 }) {
            ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
              Text(group.section.title)
                .fontSize(12)
                .fontColor(0x0f172a)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor(0xe2e8f0)
                .borderRadius(999)
                .onClick(() => this.listScroller.scrollToItemInGroup(groupIndex, 0, true, ScrollAlign.START));
            }, (group: SectionWithCards) => group.section.id);
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 });
        }
        .backgroundColor(0xf8fafc)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off);
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(0xf1f5f9);
  }

  @Builder
  private SearchTab(): void {
    Column({ space: 10 }) {
      Text('搜索').fontSize(22).fontWeight(FontWeight.Bold);
      Text('TODO：搜索（按标题/内容过滤卡片）').fontColor(0x64748b);
    }
    .padding(16)
    .height('100%')
    .width('100%')
    .backgroundColor(0xf1f5f9);
  }

  @Builder
  private SettingsTab(): void {
    Column({ space: 10 }) {
      Text('设置').fontSize(22).fontWeight(FontWeight.Bold);
      Text('数据来源：jaywcjlove/reference').fontColor(0x64748b);
      Text('生成脚本：tools/sync_reference_docs.mjs').fontColor(0x64748b);
    }
    .padding(16)
    .height('100%')
    .width('100%')
    .backgroundColor(0xf1f5f9);
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex, controller: this.tabsController }) {
      TabContent() {
        this.DocListTab();
      }
      .tabBar('文档');

      TabContent() {
        this.ReadTab();
      }
      .tabBar('阅读');

      TabContent() {
        this.SearchTab();
      }
      .tabBar('搜索');

      TabContent() {
        this.SettingsTab();
      }
      .tabBar('设置');
    }
    .onChange((index: number) => {
      this.currentTabIndex = index;
    });
  }
}
