import type { ReferenceDocSummary } from '../../common/referenceModels';
import type { AppThemeTokens } from '../../common/appTheme';
import { getAvatarText, trimmedIcon, isRawfileIcon, isSvgIcon, iconKey, lengthToNumber } from './utils';
import { KEEP_FAVORITE_AND_RECENT_ENTRY_IN_FULL_CATALOG_LIST } from './constants';

@Component
export struct DocListTab {
  @Link currentTabIndex: number;
  @Link loading: boolean;
  @Link errorText: string;
  @Link catalogSearchQuery: string;
  @Link catalogSearchResults: Array<ReferenceDocSummary>;
  @Link listScrollIndex: number;
  @Link searchListScrollIndex: number;
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: 'zh' | 'en';
  @Prop isLandscape: boolean;
  @Prop showSearchBar: boolean = true;
  @Prop docs: Array<ReferenceDocSummary> = [];
  @Prop cloudDocs: Array<ReferenceDocSummary> = [];
  @Prop onlineMdDocs: Array<ReferenceDocSummary> = [];
  @Prop localMdDocs: Array<ReferenceDocSummary> = [];
  @Prop favoriteDocIds: Array<string>;
  @Prop recentDocIds: Array<string>;
  @Link iconErrorKeys: Array<string>;

  catalogSearchInputController: TextInputController = new TextInputController();
  listScroller: ListScroller = new ListScroller();
  tabsController?: TabsController;

  @State private headerAreaHeight: number = 0;

  onOpenDoc?: (docId: string, switchToReadTab: boolean) => void;
  onOpenCloudDoc?: (docId: string) => void;
  onOpenOnlineDoc?: (docId: string) => void;
  onOpenLocalDoc?: (docId: string) => void;
  onOpenDocAndQuiz?: (docId: string) => void;
  onOpenCloudDocAndQuiz?: (docId: string) => void;
  onOpenOnlineDocAndQuiz?: (docId: string) => void;
  onOpenLocalDocAndQuiz?: (docId: string) => void;
  onRebuildCatalogSearchResults?: () => void;
  onLandscapeScrollDirection?: (direction: 'up' | 'down') => void;
  onTitleAreaHeightChange?: (height: number) => void;

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private tabPadding(): Padding {
    const base: number = this.fontSize * 1;
    return this.isLandscape
      ? { left: base, right: base, top: base, bottom: 0 }
      : { left: base, right: base, top: base, bottom: 0 };
  }

  private shouldShowHeader(): boolean {
    // 横屏：tab 栏隐藏时，连带收起 title/header（标题+搜索）；竖屏始终展示 header。
    return !this.isLandscape || this.showSearchBar;
  }

  private setHeaderAreaHeight(height: number): void {
    const next: number = Math.max(0, Math.floor(height));
    if (this.headerAreaHeight === next) return;
    this.headerAreaHeight = next;
    this.onTitleAreaHeightChange?.(next);
  }

  private isOnlineDoc(docId: string): boolean {
    return docId.startsWith('online_');
  }

  private isCloudDoc(docId: string): boolean {
    return docId.startsWith('cloud_');
  }

  private isLocalDoc(docId: string): boolean {
    return docId.startsWith('local_');
  }

  private isDocFavorite(docId: string): boolean {
    return this.favoriteDocIds.indexOf(docId) >= 0;
  }

  private isDocRecent(docId: string): boolean {
    return this.recentDocIds.indexOf(docId) >= 0;
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

  private cloudBaseDocIds(): Set<string> {
    const out: Set<string> = new Set<string>();
    for (let i = 0; i < this.cloudDocs.length; i++) {
      const id: string = (this.cloudDocs[i]?.id ?? '').trim();
      if (this.isCloudDoc(id)) {
        out.add(id.slice('cloud_'.length));
      }
    }
    return out;
  }

  private filteredCatalogSearchResults(): Array<ReferenceDocSummary> {
    const cloudBaseIds = this.cloudBaseDocIds();
    const out: Array<ReferenceDocSummary> = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.catalogSearchResults.length; i++) {
      const doc = this.catalogSearchResults[i];
      const id = (doc?.id ?? '').trim();
      if (!id) continue;
      if (cloudBaseIds.has(id)) continue;
      if (seen.has(id)) continue;
      seen.add(id);
      out.push(doc);
    }
    return out;
  }

  private getCatalogDocsForDisplay(): Array<ReferenceDocSummary> {
    const merged: Array<ReferenceDocSummary> = [];
    const cloudBaseIds = this.cloudBaseDocIds();
    for (let i = 0; i < this.docs.length; i++) {
      const doc = this.docs[i];
      const id = (doc?.id ?? '').trim();
      if (id && cloudBaseIds.has(id)) continue;
      merged.push(doc);
    }
    for (let i = 0; i < this.cloudDocs.length; i++) {
      merged.push(this.cloudDocs[i]);
    }
    for (let i = 0; i < this.onlineMdDocs.length; i++) {
      merged.push(this.onlineMdDocs[i]);
    }
    for (let i = 0; i < this.localMdDocs.length; i++) {
      merged.push(this.localMdDocs[i]);
    }

    const favorites: Array<ReferenceDocSummary> = [];
    const recent: Array<ReferenceDocSummary> = [];

    for (let i = 0; i < merged.length; i++) {
      const doc = merged[i];
      if (this.isDocFavorite(doc.id)) {
        favorites.push(doc);
      } else if (this.isDocRecent(doc.id)) {
        recent.push(doc);
      }
    }

    favorites.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => {
      const ai = this.favoriteDocIds.indexOf(a.id);
      const bi = this.favoriteDocIds.indexOf(b.id);
      return ai - bi;
    });

    recent.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => {
      const ai = this.recentDocIds.indexOf(a.id);
      const bi = this.recentDocIds.indexOf(b.id);
      return ai - bi;
    });

    // “完整清单”：按字典序展示全部文档（包含收藏/最近），这样同一文档会存在多个入口。
    const allSorted: Array<ReferenceDocSummary> = KEEP_FAVORITE_AND_RECENT_ENTRY_IN_FULL_CATALOG_LIST
      ? merged.slice()
      : merged.filter((doc: ReferenceDocSummary): boolean => !this.isDocFavorite(doc.id) && !this.isDocRecent(doc.id));
    allSorted.sort((a: ReferenceDocSummary, b: ReferenceDocSummary): number => this.compareCatalogDocs(a, b));

    const result: Array<ReferenceDocSummary> = [];
    for (let i = 0; i < favorites.length; i++) {
      result.push(favorites[i]);
    }
    for (let i = 0; i < recent.length; i++) {
      result.push(recent[i]);
    }
    for (let i = 0; i < allSorted.length; i++) {
      result.push(allSorted[i]);
    }
    return result;
  }

  private hasIconError(iconKeyValue: string): boolean {
    if (!iconKeyValue) return false;
    return this.iconErrorKeys.indexOf(iconKeyValue) >= 0;
  }

  private markIconError(iconKeyValue: string): void {
    if (!iconKeyValue) return;
    if (this.hasIconError(iconKeyValue)) return;
    const next: Array<string> = this.iconErrorKeys.slice();
    next.push(iconKeyValue);
    this.iconErrorKeys = next;
  }

  private canShowLocalIcon(docId: string, icon: string | undefined): boolean {
    const s = trimmedIcon(icon);
    if (!s) return false;
    return !this.hasIconError(iconKey(docId, s));
  }

  @Builder
  private DocAvatar(docId: string, label: string, icon: string | undefined, size: number, radius: number): void {
    if (this.canShowLocalIcon(docId, icon)) {
      if (isRawfileIcon(icon)) {
        if (isSvgIcon(icon)) {
          ForEach([iconKey(docId, trimmedIcon(icon))], (_: string) => {
            Image($rawfile(trimmedIcon(icon)))
              .width(size)
              .height(size)
              .syncLoad(true)
              .fillColor(this.theme.avatarTextColor)
              .onError(() => this.markIconError(iconKey(docId, trimmedIcon(icon))));
          }, (k: string) => k);
        } else {
          ForEach([iconKey(docId, trimmedIcon(icon))], (_: string) => {
            Image($rawfile(trimmedIcon(icon)))
              .width(size)
              .height(size)
              .syncLoad(true)
              .onError(() => this.markIconError(iconKey(docId, trimmedIcon(icon))));
          }, (k: string) => k);
        }
      } else {
        if (isSvgIcon(icon)) {
          ForEach([iconKey(docId, trimmedIcon(icon))], (_: string) => {
            Image(trimmedIcon(icon))
              .width(size)
              .height(size)
              .syncLoad(true)
              .fillColor(this.theme.avatarTextColor)
              .onError(() => this.markIconError(iconKey(docId, trimmedIcon(icon))));
          }, (k: string) => k);
        } else {
          ForEach([iconKey(docId, trimmedIcon(icon))], (_: string) => {
            Image(trimmedIcon(icon))
              .width(size)
              .height(size)
              .syncLoad(true)
              .onError(() => this.markIconError(iconKey(docId, trimmedIcon(icon))));
          }, (k: string) => k);
        }
      }
    } else {
      Text(getAvatarText(label))
        .width(size)
        .height(size)
        .textAlign(TextAlign.Center)
        .fontSize(Math.floor(size * 0.4))
        .fontColor(this.theme.avatarTextColor)
        .backgroundColor(this.theme.avatarBackgroundColor)
        .borderRadius(radius);
    }
  }

  private handleOpenDoc(docId: string): void {
    if (this.isCloudDoc(docId)) {
      this.onOpenCloudDoc?.(docId);
    } else if (this.isOnlineDoc(docId)) {
      this.onOpenOnlineDoc?.(docId);
    } else if (this.isLocalDoc(docId)) {
      this.onOpenLocalDoc?.(docId);
    } else {
      this.onOpenDoc?.(docId, true);
    }
  }

  private handleOpenDocAndQuiz(docId: string): void {
    if (this.isCloudDoc(docId)) {
      this.onOpenCloudDocAndQuiz?.(docId);
    } else if (this.isOnlineDoc(docId)) {
      this.onOpenOnlineDocAndQuiz?.(docId);
    } else if (this.isLocalDoc(docId)) {
      this.onOpenLocalDocAndQuiz?.(docId);
    } else {
      this.onOpenDocAndQuiz?.(docId);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容区：当 header 展示时，为其预留高度；header 隐藏时，内容自动上移填满空间。
      Column({ space: this.fontSize * 0.6 }) {
        // 避免在“目录”页点卡片打开文档时插入顶部占位导致页面抖动：
        // 仅当目录清单本身为空且正在加载时才展示加载提示。
        if (this.loading && (this.docs.length + this.cloudDocs.length + this.onlineMdDocs.length + this.localMdDocs.length) === 0) {
          Text(this.t('加载中…', 'Loading…')).fontColor(this.theme.mutedTextColor);
        }

        if (this.errorText) {
          Text(this.errorText).fontColor(this.theme.dangerTextColor).maxLines(6);
        }

        if (this.catalogSearchQuery.trim() && this.catalogSearchResults.length === 0) {
          Text(this.t('没有匹配的文档', 'No matching docs.')).fontColor(this.theme.mutedTextColor);
        }

        List({ scroller: this.listScroller, initialIndex: this.catalogSearchQuery.trim() ? this.searchListScrollIndex : this.listScrollIndex }) {
          ForEach(this.catalogSearchQuery.trim() ? this.filteredCatalogSearchResults() : this.getCatalogDocsForDisplay(), (doc: ReferenceDocSummary) => {
            ListItem() {
              Stack({ alignContent: Alignment.TopStart }) {
                Row({ space: this.fontSize * 0.8 }) {
                  Column() {
                    this.DocAvatar(doc.id, doc.name || doc.id, doc.icon, this.fontSize * 2.5, 0);
                  }
                  .onClick(() => this.handleOpenDoc(doc.id))

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
                  }
                  .layoutWeight(1)
                  .onClick(() => this.handleOpenDoc(doc.id));

                  if (this.isLandscape) {
                    Row({ space: this.fontSize * 0.8 }) {
                      Text(this.t('打开', 'Open'))
                        .fontSize(this.fontSize * 0.8)
                        .fontColor(this.theme.accentColor)
                        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                        .border({ width: 1, color: this.theme.accentColor })
                        .borderRadius(this.fontSize * 0.4)
                        .onClick(() => this.handleOpenDoc(doc.id));
                      Text(this.t('测验', 'Quiz'))
                        .fontSize(this.fontSize * 0.8)
                        .fontColor(this.theme.accentColor)
                        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                        .border({ width: 1, color: this.theme.accentColor })
                        .borderRadius(this.fontSize * 0.4)
                        .onClick(() => this.handleOpenDocAndQuiz(doc.id));
                    }
                  } else {
                    Column({ space: this.fontSize * 0.5 }) {
                      Text(this.t('打开', 'Open'))
                        .fontSize(this.fontSize * 0.8)
                        .fontColor(this.theme.accentColor)
                        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                        .border({ width: 1, color: this.theme.accentColor })
                        .borderRadius(this.fontSize * 0.4)
                        .onClick(() => this.handleOpenDoc(doc.id));
                      Text(this.t('测验', 'Quiz'))
                        .fontSize(this.fontSize * 0.8)
                        .fontColor(this.theme.accentColor)
                        .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                        .border({ width: 1, color: this.theme.accentColor })
                        .borderRadius(this.fontSize * 0.4)
                        .onClick(() => this.handleOpenDocAndQuiz(doc.id));
                    }
                    .alignItems(HorizontalAlign.End);
                  }
                }
                .padding(this.fontSize * 1)
                .width('100%');

                Row({ space: this.fontSize * 0.3 }) {
                  if (this.isDocFavorite(doc.id)) {
                    Text(this.t('收藏', 'Fav'))
                      .fontSize(this.fontSize * 0.65)
                      .fontColor(0xffffffff)
                      .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                      .backgroundColor(0xffF59E0B)
                      .borderRadius({
                        topLeft: this.fontSize * 0.7,
                        topRight: this.fontSize * 0.4,
                        bottomLeft: this.fontSize * 0,
                        bottomRight: this.fontSize * 0.4
                      });
                  }
                  if (this.isDocRecent(doc.id) && !this.isDocFavorite(doc.id)) {
                    Text(this.t('最近', 'Recent'))
                      .fontSize(this.fontSize * 0.65)
                      .fontColor(0xffffffff)
                      .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                      .backgroundColor(0xff10B981)
                      .borderRadius({
                        topLeft: this.fontSize * 0.7,
                        topRight: this.fontSize * 0.4,
                        bottomLeft: this.fontSize * 0,
                        bottomRight: this.fontSize * 0.4
                      });
                  }
                  if (this.isCloudDoc(doc.id)) {
                    Text(this.t('云端', 'Cloud'))
                      .fontSize(this.fontSize * 0.65)
                      .fontColor(0xffffffff)
                      .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                      .backgroundColor(0xff0EA5E9)
                      .borderRadius({
                        topLeft: this.fontSize * 0.7,
                        topRight: this.fontSize * 0.4,
                        bottomLeft: this.fontSize * 0,
                        bottomRight: this.fontSize * 0.4
                      });
                  }
                  if (this.isOnlineDoc(doc.id)) {
                    Text(this.t('在线', 'Online'))
                      .fontSize(this.fontSize * 0.65)
                      .fontColor(0xffffffff)
                      .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                      .backgroundColor(this.theme.accentColor)
                      .borderRadius({
                        topLeft: this.fontSize * 0.7,
                        topRight: this.fontSize * 0.4,
                        bottomLeft: this.fontSize * 0,
                        bottomRight: this.fontSize * 0.4
                      });
                  }
                  if (this.isLocalDoc(doc.id)) {
                    Text(this.t('本地', 'Local'))
                      .fontSize(this.fontSize * 0.65)
                      .fontColor(0xffffffff)
                      .padding({ left: this.fontSize * 0.4, right: this.fontSize * 0.4, top: this.fontSize * 0.15, bottom: this.fontSize * 0.15 })
                      .backgroundColor(0xff6366F1)
                      .borderRadius({
                        topLeft: this.fontSize * 0.7,
                        topRight: this.fontSize * 0.4,
                        bottomLeft: this.fontSize * 0,
                        bottomRight: this.fontSize * 0.4
                      });
                  }
                }
              }
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.8);
            }
            .margin({ bottom: this.fontSize * 0.6 });
          }, (doc: ReferenceDocSummary, index: number) => `${this.lang}:${doc.id}:${index}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
        .onScrollIndex((start: number, _end: number) => {
          const isSearching: boolean = !!this.catalogSearchQuery.trim();
          if (isSearching) {
            const previous: number = this.searchListScrollIndex;
            if (previous !== start) {
              if (this.isLandscape) {
                this.onLandscapeScrollDirection?.(start > previous ? 'up' : 'down');
              }
              this.searchListScrollIndex = start;
            }
          } else {
            const previous: number = this.listScrollIndex;
            if (previous !== start) {
              if (this.isLandscape) {
                this.onLandscapeScrollDirection?.(start > previous ? 'up' : 'down');
              }
              this.listScrollIndex = start;
            }
          }
        });
      }
      .padding({
        left: this.tabPadding().left,
        right: this.tabPadding().right,
        top: lengthToNumber(this.tabPadding().top ?? 0) + (this.shouldShowHeader() ? (this.headerAreaHeight + this.fontSize * 0.6) : 0),
        bottom: this.tabPadding().bottom
      })
      .height('100%')
      .width('100%');

      // Header（标题+搜索）：横屏 tab 栏隐藏时同步收起。
      Column() {
        Column({ space: this.fontSize * 0.6 }) {
          Text(this.t('开发速查', 'Quick Reference'))
            .fontSize(this.fontSize * 1.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.accentColor);

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
                this.onRebuildCatalogSearchResults?.();
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
        // 横屏 tab 自动隐藏的判定依赖标题区高度：这里把“标题+搜索栏”整体计入，避免误判为 pinned。
        .onAreaChange((_: Area, area: Area) => {
          this.setHeaderAreaHeight(lengthToNumber(area.height));
        });
      }
      .padding({ left: this.tabPadding().left, right: this.tabPadding().right, top: lengthToNumber(this.tabPadding().top ?? 0), bottom: 0 })
      .opacity(this.shouldShowHeader() ? 1 : 0)
      .translate({ x: 0, y: this.shouldShowHeader() ? 0 : -(this.headerAreaHeight + this.fontSize * 0.6 + lengthToNumber(this.tabPadding().top ?? 0)) })
      .enabled(this.shouldShowHeader());
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }
}
