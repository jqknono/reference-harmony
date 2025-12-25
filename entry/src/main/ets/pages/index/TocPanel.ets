import type { ReferenceCardData } from '../../common/referenceModels';
import type { AppThemeTokens } from '../../common/appTheme';
import type { SectionWithCards } from './types';
import { getTocCardTitle } from './utils';

@Component
export struct TocPanel {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: 'zh' | 'en';
  @Prop selectedDocId: string;
  @Prop sectionCards: Array<SectionWithCards>;
  @Link listScrollIndex: number;

  listScroller: ListScroller = new ListScroller();

  onClose?: () => void;
  onScrollToCard?: (groupIndex: number, cardIndex: number) => void;

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  build() {
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
              this.onClose?.();
            });
        }
        .width('100%')
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.8 });

        List({ scroller: this.listScroller, initialIndex: this.listScrollIndex }) {
          ForEach(this.sectionCards, (group: SectionWithCards, groupIndex: number) => {
            ListItemGroup() {
              ListItem() {
                Row({ space: this.fontSize * 1 }) {
                  Text('#')
                    .fontSize(this.fontSize * 1)
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
                  Text(getTocCardTitle(card))
                    .fontSize(this.fontSize * 1)
                    .fontColor(this.theme.textColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: this.fontSize * 1.8, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
                    .width('100%')
                    .onClick(() => {
                      this.onScrollToCard?.(groupIndex, cardIndex);
                    });
                }
              }, (card: ReferenceCardData) => `toc:${this.selectedDocId}:${card.id}`);
            }
          }, (group: SectionWithCards) => `toc:${this.selectedDocId}:${group.section.id}`);
        }
        .layoutWeight(1)
        .divider({ strokeWidth: this.fontSize * 0.0001, color: 0x00000000 })
        .onScrollIndex((start: number, _end: number) => {
          if (this.listScrollIndex !== start) {
            this.listScrollIndex = start;
          }
        });
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
      this.onClose?.();
    });
  }
}
