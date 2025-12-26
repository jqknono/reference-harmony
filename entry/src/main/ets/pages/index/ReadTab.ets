import type { ReferenceDoc, ReferenceCardData } from '../../common/referenceModels';
import type { AppThemeTokens } from '../../common/appTheme';
import type { SectionWithCards } from './types';
import { ReferenceCard } from '../../components/ReferenceCard';
import { makeCardMargin, getAvatarText, trimmedIcon, isRawfileIcon, isSvgIcon, isRemoteIcon, iconKey, getTocCardTitle } from './utils';

@Component
export struct ReadTab {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: 'zh' | 'en';
  @Prop isLandscape: boolean;
  @Prop learningModeEnabled: boolean;
  @Link searchQuery: string;
  @Link searchSectionCards: Array<SectionWithCards>;
  @Link searchResultCount: number;
  @Link searchNavSectionIndex: number;
  @Link sectionCards: Array<SectionWithCards>;
  @Link loading: boolean;
  @Link errorText: string;
  @Link iconErrorKeys: Array<string>;
  @Link pendingTocScrollGroupIndex: number;
  @Link pendingTocScrollItemIndex: number;
  @Link listScrollIndex: number;
  @Link listSearchScrollIndex: number;
  @Link listScrollItemIndexInGroup: number;
  @Link listSearchScrollItemIndexInGroup: number;

  @Prop selectedDoc: ReferenceDoc | null = null;
  @Prop selectedDocId: string = '';
  @Prop selectedDocIcon: string = '';
  @Prop selectedDocAvatarVersion: number = 0;
  @Prop favoriteDocIds: Array<string> = [];

  listScroller: ListScroller = new ListScroller();
  listSearchScroller: ListScroller = new ListScroller();
  listSectionNavScroller: Scroller = new Scroller();
  listCardNavScroller: Scroller = new Scroller();
  docSearchInputController: TextInputController = new TextInputController();

  // 旋转/重建时，List 可能会先回调一次 index=0，导致把父组件保存的滚动位置覆盖为 0。
  // 这里用一个轻量的“门闩”：等 onAppear 根据已保存的锚点恢复完滚动后，再开始同步滚动状态。
  private enableListIndexSync: boolean = false;
  private enableSearchListIndexSync: boolean = false;

  onToggleDocFavorite?: (docId: string) => void;
  onShowTocPanel?: () => void;
  onRebuildSearchResults?: () => void;
  onLandscapeScrollDirection?: (direction: 'up' | 'down') => void;

  private getHostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private isDocFavorite(docId: string): boolean {
    return this.favoriteDocIds.indexOf(docId) >= 0;
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
    if (isRemoteIcon(s)) return false;
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

  build() {
    Column({ space: this.fontSize * 0.6 }) {
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
              .fontColor(this.theme.accentColor);

            if (this.selectedDoc && this.selectedDoc.title && this.selectedDoc.title !== this.selectedDoc.name) {
              Text(this.selectedDoc.title).fontSize(this.fontSize * 0.8).fontColor(this.theme.mutedTextColor).maxLines(2);
            }
          }
          .layoutWeight(1);

          if (this.selectedDocId) {
            Text(this.isDocFavorite(this.selectedDocId) ? '★' : '☆')
              .fontSize(this.fontSize * 1.5)
              .fontColor(this.isDocFavorite(this.selectedDocId) ? 0xffF59E0B : this.theme.mutedTextColor)
              .onClick(() => {
                this.onToggleDocFavorite?.(this.selectedDocId);
              });
          }

          Text(this.t('目录', 'TOC'))
            .fontSize(this.fontSize * 1)
            .fontColor(this.theme.accentColor)
            .onClick(() => {
              this.onShowTocPanel?.();
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
                this.onRebuildSearchResults?.();
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
                  this.onRebuildSearchResults?.();
                });
            }
          }
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
        }
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

        List({ scroller: this.listSearchScroller, initialIndex: this.listSearchScrollIndex }) {
          ForEach(this.searchSectionCards, (group: SectionWithCards, groupIndex: number) => {
            ListItemGroup() {
              ListItem() {
                Row({ space: this.fontSize * 0.6 }) {
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
                    hostContext: this.getHostContext(),
                    margin: makeCardMargin(this.fontSize),
                  })
                  ;
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:search:${card.id}:${this.learningModeEnabled}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:search:${group.section.id}`);
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 })
        .onScrollVisibleContentChange((startInfo: VisibleListContentInfo, _endInfo: VisibleListContentInfo) => {
          if (!this.enableSearchListIndexSync) return;

          const groupIndex: number = startInfo.index;
          const previousGroupIndex: number = this.listSearchScrollIndex;
          if (previousGroupIndex !== groupIndex) {
            if (this.isLandscape) {
              this.onLandscapeScrollDirection?.(groupIndex > previousGroupIndex ? 'up' : 'down');
            }
            this.listSearchScrollIndex = groupIndex;
          }

          const cardsLen: number = this.searchSectionCards[groupIndex]?.cards?.length ?? 0;
          let itemIndexInGroup: number = typeof startInfo.itemIndexInGroup === 'number' ? startInfo.itemIndexInGroup : 0;
          if (cardsLen > 0) {
            // indexInGroup: 0=组内标题，1..N=card；为了锚点到 card，这里将 0 归一到 1。
            if (itemIndexInGroup <= 0) {
              itemIndexInGroup = 1;
            } else if (itemIndexInGroup > cardsLen) {
              itemIndexInGroup = cardsLen;
            }
          }

          const previousItemIndexInGroup: number = this.listSearchScrollItemIndexInGroup;
          if (previousItemIndexInGroup !== itemIndexInGroup) {
            if (this.isLandscape && groupIndex === previousGroupIndex) {
              this.onLandscapeScrollDirection?.(itemIndexInGroup > previousItemIndexInGroup ? 'up' : 'down');
            }
            this.listSearchScrollItemIndexInGroup = itemIndexInGroup;
          }
        })
        .onAppear(() => {
          const groupIndex: number = this.listSearchScrollIndex;
          const cardsLen: number = this.searchSectionCards[groupIndex]?.cards?.length ?? 0;
          if (groupIndex >= 0 && groupIndex < this.searchSectionCards.length && cardsLen > 0) {
            let itemIndexInGroup: number = this.listSearchScrollItemIndexInGroup;
            if (itemIndexInGroup <= 0) {
              itemIndexInGroup = 1;
            } else if (itemIndexInGroup > cardsLen) {
              itemIndexInGroup = cardsLen;
            }
            this.listSearchScroller.scrollToItemInGroup(groupIndex, itemIndexInGroup, false, ScrollAlign.START);
          }
          this.enableSearchListIndexSync = true;
        });

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
                    Text(getTocCardTitle(card))
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
          .width('100%')
          .backgroundColor(this.theme.surfaceMutedBackgroundColor);
        }
      } else {
        List({ scroller: this.listScroller, initialIndex: this.listScrollIndex }) {
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
                    hostContext: this.getHostContext(),
                    margin: makeCardMargin(this.fontSize),
                  })
                  ;
                }
              }, (card: ReferenceCardData) => `${this.selectedDocId}:${card.id}:${this.learningModeEnabled}`);
            }
          }, (group: SectionWithCards) => `${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 })
        .onScrollVisibleContentChange((startInfo: VisibleListContentInfo, _endInfo: VisibleListContentInfo) => {
          if (!this.enableListIndexSync) return;

          const groupIndex: number = startInfo.index;
          const previousGroupIndex: number = this.listScrollIndex;
          if (previousGroupIndex !== groupIndex) {
            if (this.isLandscape) {
              this.onLandscapeScrollDirection?.(groupIndex > previousGroupIndex ? 'up' : 'down');
            }
            this.listScrollIndex = groupIndex;
          }

          const cardsLen: number = this.sectionCards[groupIndex]?.cards?.length ?? 0;
          let itemIndexInGroup: number = typeof startInfo.itemIndexInGroup === 'number' ? startInfo.itemIndexInGroup : 0;
          if (cardsLen > 0) {
            // indexInGroup: 0=组内标题，1..N=card；为了锚点到 card，这里将 0 归一到 1。
            if (itemIndexInGroup <= 0) {
              itemIndexInGroup = 1;
            } else if (itemIndexInGroup > cardsLen) {
              itemIndexInGroup = cardsLen;
            }
          }

          const previousItemIndexInGroup: number = this.listScrollItemIndexInGroup;
          if (previousItemIndexInGroup !== itemIndexInGroup) {
            if (this.isLandscape && groupIndex === previousGroupIndex) {
              this.onLandscapeScrollDirection?.(itemIndexInGroup > previousItemIndexInGroup ? 'up' : 'down');
            }
            this.listScrollItemIndexInGroup = itemIndexInGroup;
          }
        })
        .onAppear(() => {
          if (this.pendingTocScrollGroupIndex >= 0 && this.pendingTocScrollItemIndex >= 0) {
            const groupIndex: number = this.pendingTocScrollGroupIndex;
            const itemIndex: number = this.pendingTocScrollItemIndex;
            this.pendingTocScrollGroupIndex = -1;
            this.pendingTocScrollItemIndex = -1;
            this.listScroller.scrollToItemInGroup(groupIndex, itemIndex, true, ScrollAlign.START);
          } else {
            const groupIndex: number = this.listScrollIndex;
            const cardsLen: number = this.sectionCards[groupIndex]?.cards?.length ?? 0;
            if (groupIndex >= 0 && groupIndex < this.sectionCards.length && cardsLen > 0) {
              let itemIndexInGroup: number = this.listScrollItemIndexInGroup;
              if (itemIndexInGroup <= 0) {
                itemIndexInGroup = 1;
              } else if (itemIndexInGroup > cardsLen) {
                itemIndexInGroup = cardsLen;
              }
              this.listScroller.scrollToItemInGroup(groupIndex, itemIndexInGroup, false, ScrollAlign.START);
            }
          }
          this.enableListIndexSync = true;
        });
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }
}
