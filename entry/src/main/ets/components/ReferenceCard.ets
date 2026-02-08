import type { ReferenceCardData } from '../common/referenceModels';
import type { AppThemeTokens } from '../common/appTheme';
import { MarkdownView } from './MarkdownView';
import { decodeIfEncoded } from '../common/encodedContent';

interface ReferenceCardParams {
  card: ReferenceCardData;
  theme: AppThemeTokens;
  hostContext: object | undefined;
  fontSize?: number;
  unboundedTableColumns?: boolean;
  learningMode?: boolean;
  margin?: Margin | number;
  // When a section/group header already shows the same title, suppress the per-card title to avoid duplicates.
  hideTitle?: boolean;
}

@Builder
export function ReferenceCard($$: ReferenceCardParams): void {
  Column({ space: ($$.fontSize ?? 15) * 0.5 }) {
    if (!($$.hideTitle ?? false) && decodeIfEncoded($$.card.title, $$.card.encoded === true).trim()) {
      Row() {
        Column() {
          MarkdownView({
            markdown: decodeIfEncoded($$.card.title, $$.card.encoded === true),
            inlineOnly: true,
            fontSize: $$.fontSize ?? 15,
            fontColor: $$.theme.cardTitleColor,
            fontWeight: FontWeight.Bold,
            theme: $$.theme,
            unboundedTableColumns: $$.unboundedTableColumns ?? false,
            learningMode: $$.learningMode ?? false,
            hostContext: $$.hostContext,
          });
        }
        .layoutWeight(1);
      }
    }

    if ($$.card.kind === 'qa') {
      Column({ space: ($$.fontSize ?? 15) * 0.5 }) {
        if (decodeIfEncoded($$.card.front, $$.card.encoded === true).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded($$.card.front, $$.card.encoded === true),
            inlineOnly: true,
            fontSize: $$.fontSize ?? 15,
            fontColor: $$.theme.qaFrontTextColor,
            fontWeight: FontWeight.Medium,
            theme: $$.theme,
            unboundedTableColumns: $$.unboundedTableColumns ?? false,
            learningMode: $$.learningMode ?? false,
            hostContext: $$.hostContext,
          });
        }

        if (decodeIfEncoded($$.card.back, $$.card.encoded === true).trim()) {
          MarkdownView({
            markdown: decodeIfEncoded($$.card.back, $$.card.encoded === true),
            fontSize: $$.fontSize ?? 15,
            fontColor: $$.theme.qaBackTextColor,
            theme: $$.theme,
            unboundedTableColumns: $$.unboundedTableColumns ?? false,
            learningMode: $$.learningMode ?? false,
            hostContext: $$.hostContext,
          });
        }
      }
    } else if ($$.card.kind === 'code') {
      Text(decodeIfEncoded($$.card.code, $$.card.encoded === true))
        .fontFamily('monospace')
        .fontSize(($$.fontSize ?? 15) * 0.8)
        .fontColor($$.theme.markdown.codeTextColor)
        .textAlign(TextAlign.Start)
        .width('100%')
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.Clip });
    } else {
      MarkdownView({
        markdown: decodeIfEncoded($$.card.body, $$.card.encoded === true),
        fontSize: $$.fontSize ?? 15,
        fontColor: $$.theme.textColor,
        theme: $$.theme,
        unboundedTableColumns: $$.unboundedTableColumns ?? false,
        learningMode: $$.learningMode ?? false,
        hostContext: $$.hostContext,
      });
    }
  }
  .padding(($$.fontSize ?? 15) * 1)
  .backgroundColor($$.theme.surfaceBackgroundColor)
  .borderRadius(($$.fontSize ?? 15) * 0.8)
  .border({ width: ($$.fontSize ?? 15) * 0.06, color: $$.theme.borderColor })
  .margin($$.margin ?? 0);
}
