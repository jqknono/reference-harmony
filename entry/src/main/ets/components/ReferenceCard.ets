import type { ReferenceCardData, ReferenceLang } from '../common/referenceModels';
import type { AppThemeTokens } from '../common/appTheme';
import { MarkdownView } from './MarkdownView';
import { decodeIfEncoded } from '../common/encodedContent';

@Component
export struct ReferenceCard {
  @Prop card: ReferenceCardData;
  @Prop lang: ReferenceLang;
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number = 15;
  @Prop unboundedTableColumns: boolean = false;

  private isEncoded(): boolean {
    return this.card.encoded === true;
  }

  @Builder
  private Body(): void {
    if (this.card.kind === 'qa') {
      Column({ space: this.fontSize * 0.5 }) {
        if (decodeIfEncoded(this.card.front, this.isEncoded()).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded(this.card.front, this.isEncoded()),
            inlineOnly: true,
            fontSize: this.fontSize,
            fontColor: this.theme.qaFrontTextColor,
            fontWeight: FontWeight.Medium,
            theme: this.theme,
            unboundedTableColumns: this.unboundedTableColumns,
          });
        }
        if (decodeIfEncoded(this.card.back, this.isEncoded()).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded(this.card.back, this.isEncoded()),
            fontSize: this.fontSize,
            fontColor: this.theme.qaBackTextColor,
            theme: this.theme,
            unboundedTableColumns: this.unboundedTableColumns,
          });
        }
      }
    } else if (this.card.kind === 'code') {
      Text(decodeIfEncoded(this.card.code, this.isEncoded()))
        .fontFamily('monospace')
        .fontSize(this.fontSize * 0.8)
        .fontColor(this.theme.markdown.codeTextColor)
        .textAlign(TextAlign.Start)
        .width('100%')
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else {
      MarkdownView({
        markdown: decodeIfEncoded(this.card.body, this.isEncoded()),
        fontSize: this.fontSize,
        fontColor: this.theme.textColor,
        theme: this.theme,
        unboundedTableColumns: this.unboundedTableColumns,
      });
    }
  }

  build() {
    Column({ space: this.fontSize * 0.5 }) {
      Row() {
        MarkdownView({
          markdown: decodeIfEncoded(this.card.title, this.isEncoded()),
          inlineOnly: true,
          fontSize: this.fontSize,
          fontColor: this.theme.cardTitleColor,
          fontWeight: FontWeight.Bold,
          theme: this.theme,
          unboundedTableColumns: this.unboundedTableColumns,
        })
          .layoutWeight(1);
      }

      this.Body()
    }
    .padding(this.fontSize * 1)
    .backgroundColor(this.theme.surfaceBackgroundColor)
    .borderRadius(this.fontSize * 0.8)
    .shadow({ radius: this.fontSize * 0.4, color: this.theme.shadowColor, offsetX: 0, offsetY: 2 });
  }
}
