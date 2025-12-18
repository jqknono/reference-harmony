import type { ReferenceCardData, ReferenceLang } from '../common/referenceModels';
import type { AppThemeTokens } from '../common/appTheme';
import { MarkdownView } from './MarkdownView';
import { decodeIfEncoded } from '../common/encodedContent';

@Component
export struct ReferenceCard {
  @Prop card: ReferenceCardData;
  @Prop lang: ReferenceLang;
  @Prop theme: AppThemeTokens;

  @Builder
  private Body(): void {
    if (this.card.kind === 'qa') {
      Column({ space: 8 }) {
        if (decodeIfEncoded(this.card.front, this.card.encoded).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded(this.card.front, this.card.encoded),
            inlineOnly: true,
            fontSize: 15,
            fontColor: this.theme.qaFrontTextColor,
            fontWeight: FontWeight.Medium,
            theme: this.theme,
          });
        }
        if (decodeIfEncoded(this.card.back, this.card.encoded).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded(this.card.back, this.card.encoded),
            fontSize: 15,
            fontColor: this.theme.qaBackTextColor,
            theme: this.theme,
          });
        }
      }
    } else if (this.card.kind === 'code') {
      Text(decodeIfEncoded(this.card.code, this.card.encoded))
        .fontFamily('monospace')
        .fontSize(13)
        .fontColor(this.theme.markdown.codeTextColor)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else {
      MarkdownView({
        markdown: decodeIfEncoded(this.card.body, this.card.encoded),
        fontSize: 15,
        fontColor: this.theme.textColor,
        theme: this.theme,
      });
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        MarkdownView({
          markdown: decodeIfEncoded(this.card.title, this.card.encoded),
          inlineOnly: true,
          fontSize: 16,
          fontColor: this.theme.titleColor,
          fontWeight: FontWeight.Medium,
          theme: this.theme,
        })
          .layoutWeight(1);
      }

      this.Body()
    }
    .padding(14)
    .backgroundColor(this.theme.surfaceBackgroundColor)
    .borderRadius(14)
    .shadow({ radius: 8, color: this.theme.shadowColor, offsetX: 0, offsetY: 2 });
  }
}
