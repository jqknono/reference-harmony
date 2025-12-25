import type { AppThemeTokens } from '../../common/appTheme';

export interface TabBarItemProps {
  index: number;
  currentTabIndex: number;
  fontSize: number;
  theme: AppThemeTokens;
  getTabLabel: (index: number) => string;
}

@Builder
export function TabBarItem(props: TabBarItemProps): void {
  Column() {
    Text(props.getTabLabel(props.index))
      .fontSize(props.fontSize * 1)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .fontColor(props.currentTabIndex === props.index ? props.theme.accentColor : props.theme.mutedTextColor)
      .fontWeight(props.currentTabIndex === props.index ? FontWeight.Medium : FontWeight.Normal);
  }
  .layoutWeight(1)
  .padding({ top: props.fontSize * 0.5, bottom: props.fontSize * 0.5, left: props.fontSize * 5, right: props.fontSize * 5 });
}

