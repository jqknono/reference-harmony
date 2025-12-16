import type { ReferenceCardData, ReferenceLang } from '../common/referenceModels';

@Component
export struct ReferenceCard {
  @Prop card: ReferenceCardData;
  @Prop lang: ReferenceLang;

  @State private showBack: boolean = false;

  @Builder
  private Body(): void {
    if (this.card.kind === 'qa') {
      Text(this.showBack ? (this.card.back ?? '') : (this.card.front ?? ''))
        .fontSize(15)
        .fontColor(this.showBack ? 0x111111 : 0x222222)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else if (this.card.kind === 'code') {
      Text(this.card.code ?? '')
        .fontFamily('monospace')
        .fontSize(13)
        .fontColor(0x1f2328)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else {
      Text(this.card.body ?? '')
        .fontSize(15)
        .fontColor(0x222222)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.card.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(0x0f172a)
          .layoutWeight(1);

        if (this.card.kind === 'qa') {
          Text(this.showBack ? (this.lang === 'en' ? 'Back' : '背面') : (this.lang === 'en' ? 'Front' : '正面'))
            .fontSize(12)
            .fontColor(0x64748b);
        }
      }

      this.Body()
    }
    .padding(14)
    .backgroundColor(0xffffff)
    .borderRadius(14)
    .shadow({ radius: 8, color: 0x14000000, offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (this.card.kind !== 'qa') {
        return;
      }
      this.showBack = !this.showBack;
    });
  }
}
