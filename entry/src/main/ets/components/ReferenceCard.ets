import type { ReferenceCardData, ReferenceLang } from '../common/referenceModels';
import type { AppThemeTokens } from '../common/appTheme';
import { MarkdownView } from './MarkdownView';

@Component
export struct ReferenceCard {
  @Prop card: ReferenceCardData;
  @Prop lang: ReferenceLang;
  @Prop theme: AppThemeTokens;

  @State private showBack: boolean = false;

  @Builder
  private Body(): void {
    if (this.card.kind === 'qa') {
      MarkdownView({
        markdown: this.showBack ? (this.card.back ?? '') : (this.card.front ?? ''),
        fontSize: 15,
        fontColor: this.showBack ? this.theme.qaBackTextColor : this.theme.qaFrontTextColor,
        theme: this.theme,
      });
    } else if (this.card.kind === 'code') {
      Text(this.card.code ?? '')
        .fontFamily('monospace')
        .fontSize(13)
        .fontColor(this.theme.markdown.codeTextColor)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else {
      MarkdownView({ markdown: this.card.body ?? '', fontSize: 15, fontColor: this.theme.textColor, theme: this.theme });
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        MarkdownView({
          markdown: this.card.title,
          inlineOnly: true,
          fontSize: 16,
          fontColor: this.theme.titleColor,
          fontWeight: FontWeight.Medium,
          theme: this.theme,
        })
          .layoutWeight(1);

        if (this.card.kind === 'qa') {
          Text(this.showBack ? (this.lang === 'en' ? 'Back' : '背面') : (this.lang === 'en' ? 'Front' : '正面'))
            .fontSize(12)
            .fontColor(this.theme.mutedTextColor);
        }
      }

      this.Body()
    }
    .padding(14)
    .backgroundColor(this.theme.surfaceBackgroundColor)
    .borderRadius(14)
    .shadow({ radius: 8, color: this.theme.shadowColor, offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (this.card.kind !== 'qa') {
        return;
      }
      this.showBack = !this.showBack;
    });
  }
}
