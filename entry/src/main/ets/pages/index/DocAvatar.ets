import type { AppThemeTokens } from '../../common/appTheme';

export interface DocAvatarProps {
  docId: string;
  label: string;
  icon?: string;
  size: number;
  radius: number;
  theme: AppThemeTokens;
  canShowLocalIcon: (docId: string, icon: string | undefined) => boolean;
  isRawfileIcon: (icon: string) => boolean;
  isSvgIcon: (icon: string) => boolean;
  trimmedIcon: (icon: string | undefined) => string;
  iconKey: (docId: string, icon: string | undefined) => string;
  markIconError: (iconKey: string) => void;
}

function getAvatarText(label: string): string {
  const trimmed: string = (label ?? '').trim();
  if (!trimmed) return '?';
  const chars: Array<string> = Array.from(trimmed);
  let picked: string = chars[0] ?? '?';
  if (picked === '.' && chars.length > 1) {
    picked = chars[1];
  }
  return picked.toUpperCase();
}

@Builder
export function DocAvatar(props: DocAvatarProps): void {
  if (props.canShowLocalIcon(props.docId, props.icon)) {
    if (props.isRawfileIcon(props.trimmedIcon(props.icon))) {
      if (props.isSvgIcon(props.trimmedIcon(props.icon))) {
        ForEach([props.iconKey(props.docId, props.trimmedIcon(props.icon))], (_: string) => {
          Image($rawfile(props.trimmedIcon(props.icon)))
            .width(props.size)
            .height(props.size)
            .syncLoad(true)
            .fillColor(props.theme.avatarTextColor)
            .onError(() => props.markIconError(props.iconKey(props.docId, props.trimmedIcon(props.icon))));
        }, (k: string) => k);
      } else {
        ForEach([props.iconKey(props.docId, props.trimmedIcon(props.icon))], (_: string) => {
          Image($rawfile(props.trimmedIcon(props.icon)))
            .width(props.size)
            .height(props.size)
            .syncLoad(true)
            .onError(() => props.markIconError(props.iconKey(props.docId, props.trimmedIcon(props.icon))));
        }, (k: string) => k);
      }
    } else {
      if (props.isSvgIcon(props.trimmedIcon(props.icon))) {
        ForEach([props.iconKey(props.docId, props.trimmedIcon(props.icon))], (_: string) => {
          Image(props.trimmedIcon(props.icon))
            .width(props.size)
            .height(props.size)
            .syncLoad(true)
            .fillColor(props.theme.avatarTextColor)
            .onError(() => props.markIconError(props.iconKey(props.docId, props.trimmedIcon(props.icon))));
        }, (k: string) => k);
      } else {
        ForEach([props.iconKey(props.docId, props.trimmedIcon(props.icon))], (_: string) => {
          Image(props.trimmedIcon(props.icon))
            .width(props.size)
            .height(props.size)
            .syncLoad(true)
            .onError(() => props.markIconError(props.iconKey(props.docId, props.trimmedIcon(props.icon))));
        }, (k: string) => k);
      }
    }
  } else {
    Text(getAvatarText(props.label))
      .width(props.size)
      .height(props.size)
      .textAlign(TextAlign.Center)
      .fontSize(Math.floor(props.size * 0.4))
      .fontColor(props.theme.avatarTextColor)
      .backgroundColor(props.theme.avatarBackgroundColor)
      .borderRadius(props.radius);
  }
}

