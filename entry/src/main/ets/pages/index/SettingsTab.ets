import type { AppThemeTokens } from '../../common/appTheme';
import type { ReferenceLang } from '../../common/referenceModels';
import type { OnlineMdLink } from '../../common/onlineMdModels';
import { openExternalLink } from '../../common/openExternalLink';
import { formatDocCount } from './utils';
import { ENABLE_ORIENTATION_MODE_SETTING, PRIVACY_STATEMENT_URL, SHOW_IMPORT_MARKDOWN_URL_SETTING } from './constants';
import webview from '@ohos.web.webview';
import bundleManager from '@ohos.bundle.bundleManager';

type ThemePreference = 'dark' | 'light' | 'system';

const APP_DISPLAY_NAME_ZH: string = '开发速查';
const APP_DISPLAY_NAME_EN: string = 'Quick Reference';
const FALLBACK_VERSION_NAME: string = '0.16.0';
const FALLBACK_VERSION_CODE: number = 2026010221;
const DEVELOPER_NAME: string = '李偲';
const ONLINE_FILE_LIST_URL: string = 'https://reference.jqknono.com/';

interface BundleInfoLike {
  versionName?: string;
  versionCode?: number;
}

@Component
export struct SettingsTab {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: ReferenceLang;
  @Prop isLandscape: boolean;
  @Prop themeId: ThemePreference;
  @Prop orientationMode: 'portrait' | 'landscape' | 'auto';
  @Prop learningModeEnabled: boolean;
  @Prop zhDocCount: number;
  @Prop enDocCount: number;

  @Link onlineMdInputUrl: string;
  @Link onlineMdParsing: boolean;
  @Link onlineMdUpdatingLinkId: string;
  @Link onlineMdParseResult: string;
  @Link onlineMdLinks: Array<OnlineMdLink>;
  @Link onlineMdCopySuccess: boolean;

  @Link localMdImporting: boolean;
  @Link localMdImportResult: string;
  @Link localMdLinks: Array<OnlineMdLink>;
  @Link localMdCopySuccess: boolean;
  @Link scrollY: number;
  @Link showPrivacyStatement: boolean;
  @Link showAbout: boolean;

  scroller: Scroller = new Scroller();
  private privacyStatementController: webview.WebviewController = new webview.WebviewController();
  @State private appVersionName: string = FALLBACK_VERSION_NAME;
  @State private appVersionCode: number = FALLBACK_VERSION_CODE;
  @State private aboutInfoLoaded: boolean = false;

  onSwitchOrientationMode?: (mode: 'portrait' | 'landscape' | 'auto') => void;
  onSwitchLang?: (lang: ReferenceLang) => void;
  onSwitchTheme?: (theme: ThemePreference) => void;
  onToggleLearningMode?: (enabled: boolean) => void;
  onParseAndAddOnlineMd?: () => void;
  onUpdateOnlineMd?: (linkId: string) => void;
  onRemoveOnlineMd?: (linkId: string) => void;
  onCopyOnlineMdUrl?: (url: string) => void;
  onImportLocalMarkdown?: () => void;
  onRemoveLocalMd?: (linkId: string) => void;
  onCopyLocalMdUri?: (uri: string) => void;
  onLandscapeScrollDirection?: (direction: 'up' | 'down') => void;

  private getHostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private ensureAboutInfoLoaded(): void {
    if (this.aboutInfoLoaded) return;
    this.aboutInfoLoaded = true;
    Promise.resolve()
      .then((): Promise<BundleInfoLike> => bundleManager.getBundleInfoForSelf(0))
      .then(
        (info: BundleInfoLike): void => {
          const versionName: string = typeof info?.versionName === 'string' ? info.versionName.trim() : '';
          const versionCode: number = typeof info?.versionCode === 'number' ? info.versionCode : -1;
          if (versionName) this.appVersionName = versionName;
          if (versionCode > 0) this.appVersionCode = versionCode;
        },
        (): void => undefined,
      );
  }

  private formatAppVersionText(): string {
    const name: string = (this.appVersionName || FALLBACK_VERSION_NAME).trim() || FALLBACK_VERSION_NAME;
    const code: number = this.appVersionCode > 0 ? this.appVersionCode : FALLBACK_VERSION_CODE;
    return `${name} (${code})`;
  }

  private tabPadding(): Padding {
    const base: number = this.fontSize * 1;
    return this.isLandscape
      ? { left: base, right: base, top: base, bottom: 0 }
      : { left: base, right: base, top: base, bottom: base };
  }

  build() {
    Stack() {
      Scroll(this.scroller) {
        Column({ space: this.fontSize * 0.8 }) {
          Text(this.t('设置', 'Settings')).fontSize(this.fontSize * 1.25).fontWeight(FontWeight.Bold).fontColor(this.theme.accentColor);

        Column({ space: 0 }) {
          if (ENABLE_ORIENTATION_MODE_SETTING) {
            Row() {
              Text(this.t('屏幕方向', 'Orientation'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);

              Row({ space: this.fontSize * 0.6 }) {
                Text(this.t('竖屏', 'Portrait'))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                  .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                  .backgroundColor(this.orientationMode === 'portrait' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                  .borderRadius(this.fontSize * 66)
                  .onClick(() => this.onSwitchOrientationMode?.('portrait'));
                Text(this.t('横屏', 'Landscape'))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                  .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                  .backgroundColor(this.orientationMode === 'landscape' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                  .borderRadius(this.fontSize * 66)
                  .onClick(() => this.onSwitchOrientationMode?.('landscape'));
                Text(this.t('自动', 'Auto'))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.orientationMode === 'auto' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                  .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                  .backgroundColor(this.orientationMode === 'auto' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                  .borderRadius(this.fontSize * 66)
                  .onClick(() => this.onSwitchOrientationMode?.('auto'));
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });

            Divider()
              .color(this.theme.borderColor)
              .strokeWidth(this.fontSize * 0.07);
          }

          Row() {
            Text(this.t('语言', 'Language'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.95);

            Row({ space: this.fontSize * 0.6 }) {
              Text(this.t('中文', '中文'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.lang === 'zh' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                .backgroundColor(this.lang === 'zh' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                .borderRadius(this.fontSize * 66)
                .onClick(() => this.onSwitchLang?.('zh'));
              Text('English')
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.lang === 'en' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                .backgroundColor(this.lang === 'en' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                .borderRadius(this.fontSize * 66)
                .onClick(() => this.onSwitchLang?.('en'));
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });

          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Row() {
            Text(this.t('主题', 'Theme'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.95);

            Row({ space: this.fontSize * 0.6 }) {
              Text(this.t('暗黑', 'Dark'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.themeId === 'dark' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                .backgroundColor(this.themeId === 'dark' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                .borderRadius(this.fontSize * 66)
                .onClick(() => this.onSwitchTheme?.('dark'));
              Text(this.t('明亮', 'Light'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.themeId === 'light' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                .backgroundColor(this.themeId === 'light' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                .borderRadius(this.fontSize * 66)
                .onClick(() => this.onSwitchTheme?.('light'));
              Text(this.t('跟随系统', 'System'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.themeId === 'system' ? this.theme.chipSelectedTextColor : this.theme.chipTextColor)
                .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
                .backgroundColor(this.themeId === 'system' ? this.theme.chipSelectedBackgroundColor : this.theme.chipBackgroundColor)
                .borderRadius(this.fontSize * 66)
                .onClick(() => this.onSwitchTheme?.('system'));
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        Column({ space: 0 }) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Text(this.t('学习模式', 'Learning Mode'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);
              Text(this.t(
                '表格仅显示首个非空列，其余内容用 * 隐藏，便于自测记忆',
                'Tables show only the first non-empty column, hiding rest with * for self-testing'
              ))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.75)
                .opacity(0.7);
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            Toggle({ type: ToggleType.Switch, isOn: this.learningModeEnabled })
              .selectedColor(this.theme.accentColor)
              .onChange((isOn: boolean) => this.onToggleLearningMode?.(isOn));
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 });
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        if (SHOW_IMPORT_MARKDOWN_URL_SETTING) {
          // 在线 Markdown 链接管理
          Column({ space: 0 }) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Text(this.t('添加在线 Markdown', 'Add Online Markdown'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);
              Text(this.t(
                '输入任意 Markdown 在线链接（需 .md/.markdown，建议 raw 直链），会自动拆分为记忆卡片；表格可在"测验"中生成题目',
                'Enter any online Markdown URL (.md/.markdown; prefer raw content URL). It becomes flashcards; tables can generate quiz questions'
              ))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.75)
                .opacity(0.7);
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.5 });

          Row({ space: this.fontSize * 0.5 }) {
            TextInput({
              text: this.onlineMdInputUrl,
              placeholder: this.t('输入 Markdown URL...', 'Enter Markdown URL...'),
            })
              .layoutWeight(1)
              .fontSize(this.fontSize * 0.8)
              .placeholderFont({ size: this.fontSize * 0.8 })
              .fontColor(this.theme.titleColor)
              .placeholderColor(this.theme.mutedTextColor)
              .enableAutoFill(false)
              .backgroundColor(this.theme.pageBackgroundColor)
              .border({ width: 1, color: this.theme.borderColor })
              .borderRadius(this.fontSize * 0.5)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .onChange((value: string) => {
                this.onlineMdInputUrl = value;
              });

            Text(this.onlineMdParsing ? this.t('解析中...', 'Parsing...') : this.t('添加', 'Add'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.onlineMdParsing ? this.theme.mutedTextColor : this.theme.chipSelectedTextColor)
              .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.4, bottom: this.fontSize * 0.4 })
              .backgroundColor(this.onlineMdParsing ? this.theme.chipBackgroundColor : this.theme.chipSelectedBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => {
                if (!this.onlineMdParsing) {
                  this.onParseAndAddOnlineMd?.();
                }
              });
          }
          .width('100%')
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });

          if (this.onlineMdParseResult) {
            Text(this.onlineMdParseResult)
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.onlineMdParseResult.includes(this.t('成功', 'success')) ? this.theme.accentColor : this.theme.dangerTextColor)
              .width('100%')
              .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });
          }

          Column({ space: this.fontSize * 0.15 }) {
            Text(this.t('示例在线清单列表', 'Sample online list'))
              .fontSize(this.fontSize * 0.8)
              .fontColor(this.theme.mutedTextColor);
            Text(ONLINE_FILE_LIST_URL)
              .fontColor(this.theme.accentColor)
              .fontSize(this.fontSize * 0.85)
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .decoration({ type: TextDecorationType.Underline })
              .onClick(() => openExternalLink(this.getHostContext(), ONLINE_FILE_LIST_URL));
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });

          if (this.onlineMdLinks.length > 0) {
            Divider()
              .color(this.theme.borderColor)
              .strokeWidth(this.fontSize * 0.07);

            Column({ space: this.fontSize * 0.3 }) {
              Row({ space: this.fontSize * 0.5 }) {
                Text(this.t(`已添加 ${this.onlineMdLinks.length} 个链接`, `${this.onlineMdLinks.length} links added`))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.theme.mutedTextColor);
                Text(this.t('（点击链接复制）', '(click link to copy)'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.mutedTextColor)
                  .opacity(0.7);
                if (this.onlineMdCopySuccess) {
                  Text(this.t('复制成功', 'Copied'))
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.accentColor)
                    .fontWeight(FontWeight.Medium);
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);

              ForEach(this.onlineMdLinks, (link: OnlineMdLink) => {
                Row({ space: this.fontSize * 0.5 }) {
                  Column({ space: this.fontSize * 0.1 }) {
                    Text(link.name)
                      .fontSize(this.fontSize * 0.9)
                      .fontColor(this.theme.titleColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(link.url)
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(this.theme.accentColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .decoration({ type: TextDecorationType.Underline });
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => this.onCopyOnlineMdUrl?.(link.url));

                  Text(this.onlineMdUpdatingLinkId === link.id ? this.t('更新中...', 'Updating...') : this.t('更新', 'Update'))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.onlineMdUpdatingLinkId === link.id ? this.theme.mutedTextColor : this.theme.accentColor)
                    .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 })
                    .onClick(() => {
                      if (this.onlineMdUpdatingLinkId === link.id) return;
                      this.onUpdateOnlineMd?.(link.id);
                    });

                  Text(this.t('删除', 'Delete'))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.dangerTextColor)
                    .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 })
                    .onClick(() => this.onRemoveOnlineMd?.(link.id));
                }
                .width('100%')
                .padding({ top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 });
              }, (link: OnlineMdLink) => link.id);
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.5, bottom: this.fontSize * 0.7 });
          }
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });
        }

        // 本地 Markdown 文件导入
        Column({ space: 0 }) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Text(this.t('导入本地 Markdown', 'Import Local Markdown'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);
              Text(this.t(
                '选择本地 .md/.markdown 文件，解析后会出现在目录中并标记为"本地"，表格可生成测验题',
                'Pick a local .md/.markdown file. It appears in catalog as "Local"; tables can generate quiz questions'
              ))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.75)
                .opacity(0.7);
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.5 });

          Row({ space: this.fontSize * 0.5 }) {
            Text(this.localMdImporting ? this.t('导入中...', 'Importing...') : this.t('选择文件', 'Pick file'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.localMdImporting ? this.theme.mutedTextColor : this.theme.chipSelectedTextColor)
              .padding({ left: this.fontSize * 0.8, right: this.fontSize * 0.8, top: this.fontSize * 0.45, bottom: this.fontSize * 0.45 })
              .backgroundColor(this.localMdImporting ? this.theme.chipBackgroundColor : this.theme.chipSelectedBackgroundColor)
              .borderRadius(this.fontSize * 66)
              .onClick(() => {
                if (!this.localMdImporting) {
                  this.onImportLocalMarkdown?.();
                }
              });
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });

          if (this.localMdImportResult) {
            Text(this.localMdImportResult)
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.localMdImportResult.includes(this.t('成功', 'success')) || this.localMdImportResult.includes(this.t('更新', 'Updated')) ? this.theme.accentColor : this.theme.dangerTextColor)
              .width('100%')
              .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, bottom: this.fontSize * 0.5 });
          }

          if (this.localMdLinks.length > 0) {
            Divider()
              .color(this.theme.borderColor)
              .strokeWidth(this.fontSize * 0.07);

            Column({ space: this.fontSize * 0.3 }) {
              Row({ space: this.fontSize * 0.5 }) {
                Text(this.t(`已导入 ${this.localMdLinks.length} 个文件`, `${this.localMdLinks.length} files imported`))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.theme.mutedTextColor);
                Text(this.t('（点击路径复制）', '(click path to copy)'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.mutedTextColor)
                  .opacity(0.7);
                if (this.localMdCopySuccess) {
                  Text(this.t('复制成功', 'Copied'))
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.accentColor)
                    .fontWeight(FontWeight.Medium);
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center);

              ForEach(this.localMdLinks, (link: OnlineMdLink) => {
                Row({ space: this.fontSize * 0.5 }) {
                  Column({ space: this.fontSize * 0.1 }) {
                    Text(link.name || this.t('本地 Markdown', 'Local Markdown'))
                      .fontSize(this.fontSize * 0.9)
                      .fontColor(this.theme.titleColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(link.url)
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(this.theme.accentColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .decoration({ type: TextDecorationType.Underline });
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => this.onCopyLocalMdUri?.(link.url));

                  Text(this.t('删除', 'Delete'))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.dangerTextColor)
                    .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 })
                    .onClick(() => this.onRemoveLocalMd?.(link.id));
                }
                .width('100%')
                .padding({ top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 });
              }, (link: OnlineMdLink) => link.id);
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.5, bottom: this.fontSize * 0.7 });
          }
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        // 业务与隐私声明
        Column({ space: 0 }) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Text(this.t('业务与隐私的声明', 'Business & Privacy Statement'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);
              Text(this.t('查看我们如何使用您的数据', 'See how we use your data'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.75)
                .opacity(0.7);
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            Text('›')
              .fontSize(this.fontSize * 1.4)
              .fontColor(this.theme.mutedTextColor)
              .opacity(0.65);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
          .onClick(() => {
            this.showAbout = false;
            this.showPrivacyStatement = true;
          });
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        // 关于
        Column({ space: 0 }) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Text(this.t('关于', 'About'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.95);
              Text(this.t('查看应用信息与版本', 'App info & version'))
                .fontColor(this.theme.mutedTextColor)
                .fontSize(this.fontSize * 0.75)
                .opacity(0.7);
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            Text('›')
              .fontSize(this.fontSize * 1.4)
              .fontColor(this.theme.mutedTextColor)
              .opacity(0.65);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
          .onClick(() => {
            this.showPrivacyStatement = false;
            this.showAbout = true;
          });
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        // 开源信息
        Column({ space: 0 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(this.t('开源地址：', 'Open Source: '))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.9);
            Text('github.com/jqknono/reference-harmony')
              .fontColor(this.theme.accentColor)
              .fontSize(this.fontSize * 0.9)
              .decoration({ type: TextDecorationType.Underline })
              .onClick(() => openExternalLink(this.getHostContext(), 'github.com/jqknono/reference-harmony'));
          }
          .width('100%')
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.7, bottom: this.fontSize * 0.5 });

          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(this.t('开源协议：', 'License: '))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.9);
            Text('GPL-3.0')
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.9);
          }
          .width('100%')
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.3, bottom: this.fontSize * 0.5 });

          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Column({ space: this.fontSize * 0.25 }) {
            Text(this.t('本应用使用了以下开源项目：', 'This app uses the following open source projects:'))
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.8)
              .opacity(0.8);
            Text('• jaywcjlove/reference (MIT)')
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.75)
              .opacity(0.7);
            Text('• Fechin/reference (GPL-3.0)')
              .fontColor(this.theme.mutedTextColor)
              .fontSize(this.fontSize * 0.75)
              .opacity(0.7);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: this.fontSize * 0.9, right: this.fontSize * 0.9, top: this.fontSize * 0.5, bottom: this.fontSize * 0.7 });
        }
        .width('100%')
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.8)
        .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });

        Column({ space: this.fontSize * 0.2 }) {
          Text(this.t(`中文备忘清单：${formatDocCount(this.zhDocCount, this.lang)}`, `ZH cheat sheets: ${formatDocCount(this.zhDocCount, this.lang)}`))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 0.85);
          Text(this.t(`英文备忘清单：${formatDocCount(this.enDocCount, this.lang)}`, `EN cheat sheets: ${formatDocCount(this.enDocCount, this.lang)}`))
            .fontColor(this.theme.mutedTextColor)
            .fontSize(this.fontSize * 0.85);
        }
        }
        .padding(this.tabPadding())
        .width('100%')
      }
      .align(Alignment.Top)
      .height('100%')
      .width('100%')
      .scrollBar(BarState.Auto)
      .onDidScroll((_xOffset: number, _yOffset: number, scrollState: ScrollState) => {
        const yOffset: number = this.scroller.currentOffset().yOffset;
        const previous: number = this.scrollY;
        const delta: number = yOffset - previous;
        const threshold: number = this.fontSize * 0.6;
        if (this.isLandscape && scrollState !== ScrollState.Idle && Math.abs(delta) >= threshold) {
          this.onLandscapeScrollDirection?.(delta > 0 ? 'up' : 'down');
        }
        if (previous !== yOffset) {
          this.scrollY = yOffset;
        }
      })
      .onAppear(() => {
        const yOffset: number = this.scrollY;
        this.scroller.scrollTo({ xOffset: 0, yOffset, animation: false });
      })
      .backgroundColor(this.theme.pageBackgroundColor);

      if (this.showPrivacyStatement) {
        Column({ space: 0 }) {
          Row() {
            Text(this.t('业务与隐私的声明', 'Business & Privacy Statement'))
              .fontSize(this.fontSize * 1.1)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.titleColor);
            Blank();
            Text(this.t('关闭', 'Close'))
              .fontSize(this.fontSize * 1)
              .fontColor(this.theme.accentColor)
              .onClick(() => {
                this.showPrivacyStatement = false;
              });
          }
          .width('100%')
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.8 });

          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Web({ src: PRIVACY_STATEMENT_URL, controller: this.privacyStatementController })
            .width('100%')
            .layoutWeight(1);
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.pageBackgroundColor);
      }

      if (this.showAbout) {
        Column({ space: 0 }) {
          Row() {
            Text(this.t('关于', 'About'))
              .fontSize(this.fontSize * 1.1)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.titleColor);
            Blank();
            Text(this.t('关闭', 'Close'))
              .fontSize(this.fontSize * 1)
              .fontColor(this.theme.accentColor)
              .onClick(() => {
                this.showAbout = false;
              });
          }
          .width('100%')
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 0.8 });

          Divider()
            .color(this.theme.borderColor)
            .strokeWidth(this.fontSize * 0.07);

          Column({ space: this.fontSize * 0.7 }) {
            Image($r('app.media.app_icon'))
              .width(this.fontSize * 4.5)
              .height(this.fontSize * 4.5)
              .borderRadius(this.fontSize * 1);

            Text(this.t(APP_DISPLAY_NAME_ZH, APP_DISPLAY_NAME_EN))
              .fontSize(this.fontSize * 1.25)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.titleColor);

            Column({ space: this.fontSize * 0.35 }) {
              Row({ space: this.fontSize * 0.5 }) {
                Text(this.t('版本', 'Version'))
                  .fontSize(this.fontSize * 0.9)
                  .fontColor(this.theme.mutedTextColor);
                Text(this.formatAppVersionText())
                  .fontSize(this.fontSize * 0.9)
                  .fontColor(this.theme.titleColor);
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween);

              Row({ space: this.fontSize * 0.5 }) {
                Text(this.t('开发者', 'Developer'))
                  .fontSize(this.fontSize * 0.9)
                  .fontColor(this.theme.mutedTextColor);
                Text(DEVELOPER_NAME)
                  .fontSize(this.fontSize * 0.9)
                  .fontColor(this.theme.titleColor);
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width('100%')
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.9, bottom: this.fontSize * 0.9 })
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.8)
            .border({ width: this.fontSize * 0.07, color: this.theme.borderColor });
          }
          .layoutWeight(1)
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1, bottom: this.fontSize * 1 })
          .onAppear(() => {
            this.ensureAboutInfoLoaded();
          });
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.pageBackgroundColor);
      }
    }
    .width('100%')
    .height('100%');
  }
}
