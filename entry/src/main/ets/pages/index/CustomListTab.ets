// 自定义清单Tab组件

import type { AppThemeTokens } from '../../common/appTheme';
import type { ReferenceLang } from '../../common/referenceModels';
import type {
  CustomList,
  CustomListItem,
  CustomListCollection,
  ReviewStats,
  ReviewGrade,
} from '../../common/customListModels';
import {
  createCustomList,
  createCustomListItem,
  getDueItems,
  calculateReviewStats,
  REVIEW_GRADE_FORGOT,
  REVIEW_GRADE_HARD,
  REVIEW_GRADE_GOOD,
  REVIEW_GRADE_EASY,
} from '../../common/customListModels';
import { CustomListRepository } from '../../common/customListRepository';
import { createDailyReminder, cancelReminder } from '../../common/calendarReminder';
import { clearCustomListBackHandler, setCustomListBackHandler } from '../../common/backHandlerRegistry';
import { lengthToNumber } from './utils';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';

type ViewMode = 'lists' | 'items' | 'review' | 'edit-list' | 'edit-item' | 'share';

const FONT_AWESOME_SOLID_FAMILY: string = 'FontAwesomeSolid';

@Component
export struct CustomListTab {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: ReferenceLang;
  @Prop isLandscape: boolean;

  @Link customLists: CustomListCollection;
  @Link scrollY: number;

  scroller: Scroller = new Scroller();
  listScroller: ListScroller = new ListScroller();
  private repository: CustomListRepository = new CustomListRepository();

  @State private viewMode: ViewMode = 'lists';
  @State private selectedList: CustomList | null = null;
  @State private selectedItem: CustomListItem | null = null;
  @State private reviewItems: Array<CustomListItem> = [];
  @State private currentReviewIndex: number = 0;
  @State private showAnswer: boolean = false;
  @State private reviewStats: ReviewStats | null = null;

  // 编辑表单状态
  @State private editListName: string = '';
  @State private editListDesc: string = '';
  @State private editItemTitle: string = '';
  @State private editItemContent: string = '';
  @State private editItemAnswer: string = '';
  @State private isEditing: boolean = false;

  // 分享相关状态
  @State private sharePassword: string = '';
  @State private shareLink: string = '';
  @State private shareCopied: boolean = false;
  @State private shareUploading: boolean = false;
  @State private shareError: string = '';
  @State private importData: string = '';
  @State private importPassword: string = '';
  @State private importError: string = '';

  // 日历提醒
  @State private reminderEnabled: boolean = false;
  @State private reminderHour: number = 8;
  @State private reminderMinute: number = 0;

  onLandscapeScrollDirection?: (direction: 'up' | 'down') => void;
  onTitleAreaHeightChange?: (height: number) => void;
  onRefreshLists?: () => void;

  private getHostContext(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private tabPadding(): Padding {
    const base: number = this.fontSize * 1;
    return this.isLandscape
      ? { left: base, right: base, top: base, bottom: 0 }
      : { left: base, right: base, top: base, bottom: base };
  }

  private async loadLists(): Promise<void> {
    const ctx = this.getHostContext();
    if (!ctx) return;
    this.customLists = await this.repository.getCustomLists(ctx);
  }

  private async createNewList(): Promise<void> {
    if (!this.editListName.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const newList = createCustomList(this.editListName.trim(), this.editListDesc.trim() || undefined);
    this.customLists = await this.repository.addList(ctx, newList);
    this.editListName = '';
    this.editListDesc = '';
    this.setViewMode('lists');
    this.onRefreshLists?.();
  }

  private async updateSelectedList(): Promise<void> {
    if (!this.selectedList || !this.editListName.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    // 处理日历提醒
    const oldReminderEnabled = this.selectedList.reminderEnabled;
    const oldCalendarEventId = this.selectedList.calendarEventId;
    let newCalendarEventId: string | undefined = oldCalendarEventId;

    if (this.reminderEnabled && !oldReminderEnabled) {
      // 启用提醒：创建新的日历提醒
      const reminderId = await createDailyReminder({
        listId: this.selectedList.id,
        listName: this.editListName.trim(),
        hour: this.reminderHour,
        minute: this.reminderMinute,
      });
      newCalendarEventId = reminderId.toString();
    } else if (!this.reminderEnabled && oldReminderEnabled && oldCalendarEventId) {
      // 禁用提醒：取消日历提醒
      await cancelReminder(parseInt(oldCalendarEventId));
      newCalendarEventId = undefined;
    } else if (this.reminderEnabled && oldReminderEnabled && oldCalendarEventId) {
      // 更新提醒时间：先取消旧的，再创建新的
      await cancelReminder(parseInt(oldCalendarEventId));
      const reminderId = await createDailyReminder({
        listId: this.selectedList.id,
        listName: this.editListName.trim(),
        hour: this.reminderHour,
        minute: this.reminderMinute,
      });
      newCalendarEventId = reminderId.toString();
    }

    this.customLists = await this.repository.updateList(ctx, this.selectedList.id, {
      name: this.editListName.trim(),
      description: this.editListDesc.trim() || undefined,
      reminderEnabled: this.reminderEnabled,
      reminderTime: this.reminderEnabled ? this.reminderHour * 60 + this.reminderMinute : undefined,
      calendarEventId: newCalendarEventId,
    });

    this.selectedList = this.customLists.lists.find(l => l.id === this.selectedList?.id) || null;
    this.setViewMode(this.selectedList ? 'items' : 'lists');
    this.onRefreshLists?.();
  }

  private async deleteList(listId: string): Promise<void> {
    const ctx = this.getHostContext();
    if (!ctx) return;

    // 取消日历提醒（如果有）
    const listToDelete = this.customLists.lists.find(l => l.id === listId);
    if (listToDelete?.calendarEventId) {
      await cancelReminder(parseInt(listToDelete.calendarEventId));
    }

    this.customLists = await this.repository.deleteList(ctx, listId);
    if (this.selectedList?.id === listId) {
      this.selectedList = null;
      this.setViewMode('lists');
    }
    this.onRefreshLists?.();
  }

  private async createNewItem(): Promise<void> {
    if (!this.selectedList || !this.editItemTitle.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const newItem = createCustomListItem(
      this.editItemTitle.trim(),
      this.editItemContent.trim(),
      this.editItemAnswer.trim() || undefined
    );

    const updatedList = await this.repository.addItem(ctx, this.selectedList.id, newItem);
    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }

    this.editItemTitle = '';
    this.editItemContent = '';
    this.editItemAnswer = '';
    this.setViewMode('items');
    this.onRefreshLists?.();
  }

  private async updateSelectedItem(): Promise<void> {
    if (!this.selectedList || !this.selectedItem || !this.editItemTitle.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.updateItem(ctx, this.selectedList.id, this.selectedItem.id, {
      title: this.editItemTitle.trim(),
      content: this.editItemContent.trim(),
      answer: this.editItemAnswer.trim() || undefined,
    });

    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }

    this.selectedItem = null;
    this.setViewMode('items');
    this.onRefreshLists?.();
  }

  private async deleteItem(itemId: string): Promise<void> {
    if (!this.selectedList) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.deleteItem(ctx, this.selectedList.id, itemId);
    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }
    this.onRefreshLists?.();
  }

  private startReview(): void {
    if (!this.selectedList) return;

    const dueItems = getDueItems(this.selectedList.items);
    if (dueItems.length === 0) {
      // 没有待复习的项目
      return;
    }

    this.reviewItems = dueItems;
    this.currentReviewIndex = 0;
    this.showAnswer = false;
    this.setViewMode('review');
  }

  private async recordReviewResult(grade: ReviewGrade): Promise<void> {
    if (!this.selectedList || this.currentReviewIndex >= this.reviewItems.length) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const currentItem = this.reviewItems[this.currentReviewIndex];
    await this.repository.recordReview(ctx, this.selectedList.id, currentItem.id, grade);

    // 刷新数据
    const updatedList = await this.repository.getList(ctx, this.selectedList.id);
    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }

    // 移动到下一个
    this.currentReviewIndex++;
    this.showAnswer = false;

    if (this.currentReviewIndex >= this.reviewItems.length) {
      // 复习完成
      this.setViewMode('items');
    }
  }

  private async generateShareLink(): Promise<void> {
    if (!this.selectedList) return;
    if (this.shareUploading) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    this.shareError = '';
    this.shareUploading = true;

    const password = this.sharePassword.trim() || undefined;
    const link = await this.repository.generateShareLink(ctx, this.selectedList.id, password).then(
      (l) => l,
      () => null,
    );
    if (link) {
      this.shareLink = link;
    } else {
      this.shareLink = '';
      this.shareError = this.t('上传失败，请检查网络后重试', 'Upload failed. Please check your network and try again.');
    }

    this.shareUploading = false;
  }

  private async copyShareLink(): Promise<void> {
    if (!this.shareLink) return;

    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareLink);
    const board = pasteboard.getSystemPasteboard();
    try {
      await board.setData(pasteData);
      this.shareCopied = true;
      setTimeout(() => {
        this.shareCopied = false;
      }, 2000);
    } catch (_) {
      this.shareCopied = false;
    }
  }

  private async importFromData(): Promise<void> {
    if (!this.importData.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    this.importError = '';

    const password = this.importPassword.trim() || undefined;
    const imported = await this.repository.importFromShareLink(ctx, this.importData.trim(), password);

    if (imported) {
      await this.loadLists();
      this.importData = '';
      this.importPassword = '';
      this.setViewMode('lists');
      this.onRefreshLists?.();
    } else {
      this.importError = this.t('导入失败，请检查数据或密码', 'Import failed, please check data or password');
    }
  }

  private formatNextReviewTime(timestamp: number): string {
    if (timestamp === 0) return this.t('立即可复习', 'Review now');

    const now = Date.now();
    const diff = timestamp - now;

    if (diff <= 0) return this.t('待复习', 'Due');

    const days = Math.floor(diff / (24 * 60 * 60 * 1000));
    const hours = Math.floor((diff % (24 * 60 * 60 * 1000)) / (60 * 60 * 1000));

    if (days > 0) {
      return this.t(`${days}天后`, `in ${days}d`);
    } else if (hours > 0) {
      return this.t(`${hours}小时后`, `in ${hours}h`);
    } else {
      return this.t('即将到期', 'Soon');
    }
  }


  private setViewMode(next: ViewMode): void {
    if (this.viewMode === next) return;
    this.viewMode = next;
  }

  private iconButtonPadding(): number {
    return this.fontSize * 0.6;
  }

  private handleBackPress(): boolean {
    if (this.viewMode === 'items') {
      this.selectedItem = null;
      this.selectedList = null;
      this.setViewMode('lists');
      return true;
    }
    if (this.viewMode === 'review') {
      this.setViewMode('items');
      return true;
    }
    if (this.viewMode === 'share') {
      this.setViewMode(this.selectedList ? 'items' : 'lists');
      return true;
    }
    if (this.viewMode === 'edit-list') {
      // 编辑已有清单：返回到项目列表；新建清单：返回到清单列表
      this.setViewMode(this.isEditing && this.selectedList ? 'items' : 'lists');
      return true;
    }
    if (this.viewMode === 'edit-item') {
      this.setViewMode('items');
      return true;
    }
    return false;
  }

  private async showDeleteListConfirm(): Promise<void> {
    try {
      const result: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: this.t('确认删除', 'Confirm Delete'),
        message: this.t('删除后无法恢复，确定要删除吗？', 'This action cannot be undone. Are you sure?'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.theme.mutedTextColor.toString() },
          { text: this.t('删除', 'Delete'), color: '#EF4444' },
        ],
      });
      if (result.index === 1 && this.selectedList) {
        await this.deleteList(this.selectedList.id);
      }
    } catch (_) {
      // ignore user cancellations or errors
    }
  }

  private async showDeleteItemConfirm(): Promise<void> {
    try {
      const result: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: this.t('确认删除', 'Confirm Delete'),
        message: this.t('删除后无法恢复，确定要删除吗？', 'This action cannot be undone. Are you sure?'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.theme.mutedTextColor.toString() },
          { text: this.t('删除', 'Delete'), color: '#EF4444' },
        ],
      });
      if (result.index === 1 && this.selectedItem) {
        await this.deleteItem(this.selectedItem.id);
        this.setViewMode('items');
      }
    } catch (_) {
      // ignore user cancellations or errors
    }
  }

  @Builder
  private ListsView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      // 标题栏
      Row() {
        Text(this.t('我的清单', 'My Lists'))
          .fontSize(this.fontSize * 1.25)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.accentColor)
          .onAreaChange((_: Area, area: Area) => {
            this.onTitleAreaHeightChange?.(lengthToNumber(area.height));
          });

        Row({ space: this.fontSize * 0.5 }) {
          // 导入按钮
          Text('\uf56f') // file-import
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 1.1)
            .fontColor(this.theme.mutedTextColor)
            .padding(this.fontSize * 0.5)
            .onClick(() => {
              this.importData = '';
              this.importPassword = '';
              this.importError = '';
              this.setViewMode('share');
            });

          // 新建按钮
          Text('\uf067') // plus
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 1.1)
            .fontColor(this.theme.accentColor)
            .padding(this.fontSize * 0.5)
            .onClick(() => {
              this.editListName = '';
              this.editListDesc = '';
              this.isEditing = false;
              this.setViewMode('edit-list');
            });
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center);

      if (this.customLists.lists.length === 0) {
        // 空状态
        Column({ space: this.fontSize }) {
          Text('\uf07c') // folder-open
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 3)
            .fontColor(this.theme.mutedTextColor);

          Text(this.t('暂无清单', 'No lists yet'))
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor);

          Text(this.t('点击右上角 + 创建第一个清单', 'Tap + to create your first list'))
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.mutedTextColor);
        }
        .width('100%')
        .padding({ top: this.fontSize * 4 })
        .alignItems(HorizontalAlign.Center);
      } else {
        // 清单列表
        List({ scroller: this.listScroller }) {
          ForEach(this.customLists.lists, (list: CustomList) => {
            ListItem() {
              Column({ space: this.fontSize * 0.3 }) {
                Row() {
                  Text(list.name)
                    .fontSize(this.fontSize)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.textColor)
                    .layoutWeight(1);

                  if (list.isShared) {
                    Text('\uf1e0') // share-alt
                      .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .margin({ right: this.fontSize * 0.5 });
                  }

                  Text('\uf105') // chevron-right
                    .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                    .fontSize(this.fontSize)
                    .fontColor(this.theme.mutedTextColor);
                }
                .width('100%')
                .alignItems(VerticalAlign.Center);

                Row({ space: this.fontSize * 0.8 }) {
                  Text(this.t(`${list.items.length} 项`, `${list.items.length} items`))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor);

                  if (list.items.length > 0) {
                    this.ListDueCount(list);
                  }
                }
                .width('100%');

                if (list.description) {
                  Text(list.description)
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                }
              }
              .width('100%')
              .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .onClick(() => {
                this.selectedList = list;
                this.reviewStats = list.items.length > 0 ? calculateReviewStats(list.items) : null;
                this.setViewMode('items');
              });
            }
            .margin({ bottom: this.fontSize * 0.5 });
          }, (list: CustomList) => list.id);
        }
        .width('100%')
        .layoutWeight(1);
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  @Builder
  private ListDueCount(list: CustomList): void {
    if (list.items.length > 0) {
      Text(this.getDueCountText(list))
        .fontSize(this.fontSize * 0.8)
        .fontColor(this.theme.accentColor)
        .fontWeight(FontWeight.Medium)
        .visibility(this.hasDueItems(list) ? Visibility.Visible : Visibility.Hidden);
    }
  }

  private getDueCountText(list: CustomList): string {
    const stats = calculateReviewStats(list.items);
    return this.t(`${stats.dueCount} 待复习`, `${stats.dueCount} due`);
  }

  private hasDueItems(list: CustomList): boolean {
    const stats = calculateReviewStats(list.items);
    return stats.dueCount > 0;
  }

  @Builder
  private ItemsView(): void {
    if (!this.selectedList) {
      Column() {
        Text(this.t('未选择清单', 'No list selected'))
          .fontSize(this.fontSize)
          .fontColor(this.theme.mutedTextColor);
      }
      .width('100%')
      .height('100%');
    } else {
      Column({ space: this.fontSize * 0.8 }) {
        // 标题栏
        Row() {
          Row({ space: this.fontSize * 0.5 }) {
            Text('\uf053') // chevron-left
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize)
              .fontColor(this.theme.accentColor)
              .padding(this.iconButtonPadding())
              .borderRadius(this.iconButtonPadding())
              .onClick(() => {
                this.selectedList = null;
                this.setViewMode('lists');
              });

            Text(this.selectedList.name)
              .fontSize(this.fontSize * 1.1)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.textColor)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .layoutWeight(1);

          Row({ space: this.fontSize * 0.3 }) {
            // 分享按钮
            Text('\uf1e0') // share-alt
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor)
              .padding(this.fontSize * 0.4)
              .onClick(() => {
                this.sharePassword = '';
                this.shareLink = '';
                this.shareCopied = false;
                this.setViewMode('share');
              });

            // 编辑清单
            Text('\uf013') // cog
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor)
              .padding(this.fontSize * 0.4)
              .onClick(() => {
                this.editListName = this.selectedList?.name || '';
                this.editListDesc = this.selectedList?.description || '';
                this.reminderEnabled = this.selectedList?.reminderEnabled || false;
                const reminderTime = this.selectedList?.reminderTime || 480;
                this.reminderHour = Math.floor(reminderTime / 60);
                this.reminderMinute = reminderTime % 60;
                this.isEditing = true;
                this.setViewMode('edit-list');
              });

            // 新建项目
            Text('\uf067') // plus
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize)
              .fontColor(this.theme.accentColor)
              .padding(this.fontSize * 0.4)
              .onClick(() => {
                this.editItemTitle = '';
                this.editItemContent = '';
                this.editItemAnswer = '';
                this.selectedItem = null;
                this.isEditing = false;
                this.setViewMode('edit-item');
              });
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        // 复习统计和开始复习按钮
        if (this.reviewStats && this.selectedList.items.length > 0) {
          Row() {
            Column({ space: this.fontSize * 0.2 }) {
              Row({ space: this.fontSize * 0.8 }) {
                Text(this.t(`待复习: ${this.reviewStats.dueCount}`, `Due: ${this.reviewStats.dueCount}`))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.reviewStats.dueCount > 0 ? this.theme.accentColor : this.theme.mutedTextColor);

                Text(this.t(`今日: ${this.reviewStats.reviewedToday}`, `Today: ${this.reviewStats.reviewedToday}`))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.theme.mutedTextColor);
              }

              if (this.reviewStats.nextReviewAt > 0 && this.reviewStats.dueCount === 0) {
                Text(this.t('下次复习: ', 'Next review: ') + this.formatNextReviewTime(this.reviewStats.nextReviewAt))
                  .fontSize(this.fontSize * 0.8)
                  .fontColor(this.theme.mutedTextColor);
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            if (this.reviewStats.dueCount > 0) {
              Button(this.t('开始复习', 'Start Review'))
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.chipSelectedTextColor)
                .backgroundColor(this.theme.accentColor)
                .borderRadius(this.fontSize * 0.5)
                .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
                .onClick(() => this.startReview());
            }
          }
          .width('100%')
          .padding({ left: this.fontSize * 0.5, right: this.fontSize * 0.5, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .borderRadius(this.fontSize * 0.5);
        }

        // 项目列表
        if (this.selectedList.items.length === 0) {
          Column({ space: this.fontSize }) {
            Text('\uf0ca') // list-ul
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize * 3)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('暂无项目', 'No items yet'))
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('点击右上角 + 添加第一个项目', 'Tap + to add your first item'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.mutedTextColor);
          }
          .width('100%')
          .padding({ top: this.fontSize * 4 })
          .alignItems(HorizontalAlign.Center);
        } else {
          List({ scroller: this.listScroller }) {
            ForEach(this.selectedList.items, (item: CustomListItem) => {
              ListItem() {
                Column({ space: this.fontSize * 0.3 }) {
                  Row() {
                    Text(item.title)
                      .fontSize(this.fontSize * 0.95)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.theme.textColor)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });

                    Text(this.formatNextReviewTime(item.nextReviewAt))
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(item.nextReviewAt <= Date.now() ? this.theme.accentColor : this.theme.mutedTextColor);
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center);

                  if (item.content) {
                    Text(item.content)
                      .fontSize(this.fontSize * 0.85)
                      .fontColor(this.theme.mutedTextColor)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                  }

                  Row({ space: this.fontSize }) {
                    Text(this.t(`复习 ${item.reviewCount} 次`, `Reviewed ${item.reviewCount}x`))
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(this.theme.mutedTextColor);

                    Text(this.t(`间隔 ${item.interval} 天`, `Interval ${item.interval}d`))
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(this.theme.mutedTextColor);
                  }
                }
                .width('100%')
                .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .onClick(() => {
                  this.selectedItem = item;
                  this.editItemTitle = item.title;
                  this.editItemContent = item.content;
                  this.editItemAnswer = item.answer || '';
                  this.isEditing = true;
                  this.setViewMode('edit-item');
                });
              }
              .margin({ bottom: this.fontSize * 0.4 });
            }, (item: CustomListItem) => item.id);
          }
          .width('100%')
          .layoutWeight(1);
        }
      }
      .width('100%')
      .height('100%')
      .padding(this.tabPadding());
    }
  }

  @Builder
  private ReviewView(): void {
    if (!this.selectedList || this.reviewItems.length === 0) {
      Column() {
        Text(this.t('无复习项目', 'No review items'))
          .fontSize(this.fontSize)
          .fontColor(this.theme.mutedTextColor);
      }
      .width('100%')
      .height('100%');
    } else {
      Column({ space: this.fontSize }) {
        // 进度条
        Row() {
          Text(`${this.currentReviewIndex + 1} / ${this.reviewItems.length}`)
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.mutedTextColor);

          Text('\uf00d') // times
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor)
            .padding(this.fontSize * 0.5)
            .onClick(() => {
              this.setViewMode('items');
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center);

        // 进度指示器
        Row() {
          ForEach(this.getProgressIndicators(), (i: number) => {
            Column()
              .width(this.fontSize * 0.5)
              .height(this.fontSize * 0.3)
              .backgroundColor(i <= this.currentReviewIndex ? this.theme.accentColor : this.theme.borderColor)
              .borderRadius(this.fontSize * 0.15)
              .margin({ right: this.fontSize * 0.2 });
          }, (i: number) => i.toString());
        }
        .width('100%');

        // 卡片内容
        Column({ space: this.fontSize }) {
          // 问题
          Column({ space: this.fontSize * 0.5 }) {
            Text(this.getCurrentReviewItemTitle())
              .fontSize(this.fontSize * 1.2)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.textColor)
              .textAlign(TextAlign.Center);

            Text(this.getCurrentReviewItemContent())
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .textAlign(TextAlign.Center)
              .visibility(this.getCurrentReviewItemContent() ? Visibility.Visible : Visibility.None);
          }
          .width('100%')
          .padding(this.fontSize * 1.5)
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .borderRadius(this.fontSize * 0.8);

          // 答案
          if (this.showAnswer) {
            Column() {
              Text(this.getCurrentReviewItemAnswer())
                .fontSize(this.fontSize)
                .fontColor(this.theme.textColor)
                .textAlign(TextAlign.Center);
            }
            .width('100%')
            .padding(this.fontSize * 1.5)
            .backgroundColor(this.theme.surfaceMutedBackgroundColor)
            .borderRadius(this.fontSize * 0.8)
            .border({ width: 1, color: this.theme.accentColor });
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center);

        // 操作按钮
        if (!this.showAnswer) {
          Button(this.t('显示答案', 'Show Answer'))
            .width('100%')
            .fontSize(this.fontSize)
            .fontColor(this.theme.chipSelectedTextColor)
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.5)
            .padding({ top: this.fontSize, bottom: this.fontSize })
            .onClick(() => {
              this.showAnswer = true;
            });
        } else {
          Column({ space: this.fontSize * 0.5 }) {
            Text(this.t('你的掌握程度如何？', 'How well did you know this?'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            Row({ space: this.fontSize * 0.5 }) {
              Button(this.t('忘记', 'Forgot'))
                .layoutWeight(1)
                .fontSize(this.fontSize * 0.85)
                .fontColor('#FFFFFF')
                .backgroundColor('#EF4444')
                .borderRadius(this.fontSize * 0.4)
                .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .onClick(() => this.recordReviewResult(REVIEW_GRADE_FORGOT));

              Button(this.t('困难', 'Hard'))
                .layoutWeight(1)
                .fontSize(this.fontSize * 0.85)
                .fontColor('#FFFFFF')
                .backgroundColor('#F59E0B')
                .borderRadius(this.fontSize * 0.4)
                .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .onClick(() => this.recordReviewResult(REVIEW_GRADE_HARD));

              Button(this.t('一般', 'Good'))
                .layoutWeight(1)
                .fontSize(this.fontSize * 0.85)
                .fontColor('#FFFFFF')
                .backgroundColor('#10B981')
                .borderRadius(this.fontSize * 0.4)
                .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .onClick(() => this.recordReviewResult(REVIEW_GRADE_GOOD));

              Button(this.t('简单', 'Easy'))
                .layoutWeight(1)
                .fontSize(this.fontSize * 0.85)
                .fontColor('#FFFFFF')
                .backgroundColor('#3B82F6')
                .borderRadius(this.fontSize * 0.4)
                .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .onClick(() => this.recordReviewResult(REVIEW_GRADE_EASY));
            }
            .width('100%');
          }
          .width('100%');
        }
      }
      .width('100%')
      .height('100%')
      .padding(this.tabPadding());
    }
  }

  private getProgressIndicators(): Array<number> {
    const result: Array<number> = [];
    for (let i = 0; i < this.reviewItems.length; i++) {
      result.push(i);
    }
    return result;
  }

  private getCurrentReviewItemTitle(): string {
    if (this.currentReviewIndex < this.reviewItems.length) {
      return this.reviewItems[this.currentReviewIndex].title;
    }
    return '';
  }

  private getCurrentReviewItemContent(): string {
    if (this.currentReviewIndex < this.reviewItems.length) {
      return this.reviewItems[this.currentReviewIndex].content;
    }
    return '';
  }

  private getCurrentReviewItemAnswer(): string {
    if (this.currentReviewIndex < this.reviewItems.length) {
      return this.reviewItems[this.currentReviewIndex].answer || '';
    }
    return '';
  }

  @Builder
  private EditListView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      // 标题栏
      Row() {
        Text('\uf053') // chevron-left
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode(this.selectedList ? 'items' : 'lists');
          });

        Text(this.isEditing ? this.t('编辑清单', 'Edit List') : this.t('新建清单', 'New List'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Text('\uf00c') // check
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.editListName.trim() ? this.theme.accentColor : this.theme.mutedTextColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            if (this.isEditing) {
              this.updateSelectedList();
            } else {
              this.createNewList();
            }
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      // 表单
      Column({ space: this.fontSize }) {
        Column({ space: this.fontSize * 0.3 }) {
          Text(this.t('名称', 'Name'))
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.mutedTextColor);

          TextInput({ placeholder: this.t('输入清单名称', 'Enter list name'), text: this.editListName })
            .fontSize(this.fontSize)
            .fontColor(this.theme.textColor)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.5)
            .padding(this.fontSize * 0.8)
            .onChange((value: string) => {
              this.editListName = value;
            });
        }

        Column({ space: this.fontSize * 0.3 }) {
          Text(this.t('描述（可选）', 'Description (optional)'))
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.mutedTextColor);

          TextArea({ placeholder: this.t('输入描述', 'Enter description'), text: this.editListDesc })
            .fontSize(this.fontSize)
            .fontColor(this.theme.textColor)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.5)
            .padding(this.fontSize * 0.8)
            .height(this.fontSize * 5)
            .onChange((value: string) => {
              this.editListDesc = value;
            });
        }

        // 日历提醒设置
        Column({ space: this.fontSize * 0.5 }) {
          Row() {
            Text(this.t('每日提醒', 'Daily Reminder'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.textColor);

            Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
              .selectedColor(this.theme.accentColor)
              .onChange((isOn: boolean) => {
                this.reminderEnabled = isOn;
              });
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center);

          if (this.reminderEnabled) {
            Row({ space: this.fontSize }) {
              Text(this.t('提醒时间', 'Reminder Time'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.mutedTextColor);

              Row() {
                TextInput({ text: this.reminderHour.toString().padStart(2, '0') })
                  .width(this.fontSize * 3)
                  .fontSize(this.fontSize)
                  .fontColor(this.theme.textColor)
                  .backgroundColor(this.theme.surfaceBackgroundColor)
                  .borderRadius(this.fontSize * 0.3)
                  .textAlign(TextAlign.Center)
                  .type(InputType.Number)
                  .onChange((value: string) => {
                    const num = parseInt(value) || 0;
                    this.reminderHour = Math.max(0, Math.min(23, num));
                  });

                Text(':')
                  .fontSize(this.fontSize)
                  .fontColor(this.theme.textColor)
                  .margin({ left: this.fontSize * 0.3, right: this.fontSize * 0.3 });

                TextInput({ text: this.reminderMinute.toString().padStart(2, '0') })
                  .width(this.fontSize * 3)
                  .fontSize(this.fontSize)
                  .fontColor(this.theme.textColor)
                  .backgroundColor(this.theme.surfaceBackgroundColor)
                  .borderRadius(this.fontSize * 0.3)
                  .textAlign(TextAlign.Center)
                  .type(InputType.Number)
                  .onChange((value: string) => {
                    const num = parseInt(value) || 0;
                    this.reminderMinute = Math.max(0, Math.min(59, num));
                  });
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center);
          }
        }
        .width('100%')
        .padding(this.fontSize * 0.8)
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.5);

        // 删除按钮（仅编辑模式）
        if (this.isEditing && this.selectedList) {
          Button(this.t('删除清单', 'Delete List'))
            .width('100%')
            .fontSize(this.fontSize)
            .fontColor('#EF4444')
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.5)
            .padding({ top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .margin({ top: this.fontSize * 2 })
            .onClick(() => {
              this.showDeleteListConfirm();
            });
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  @Builder
  private EditItemView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      // 标题栏
      Row() {
        Text('\uf053') // chevron-left
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode('items');
          });

        Text(this.isEditing ? this.t('编辑项目', 'Edit Item') : this.t('新建项目', 'New Item'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Text('\uf00c') // check
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.editItemTitle.trim() ? this.theme.accentColor : this.theme.mutedTextColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            if (this.isEditing) {
              this.updateSelectedItem();
            } else {
              this.createNewItem();
            }
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
        Column({ space: this.fontSize }) {
          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('标题', 'Title'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            TextInput({ placeholder: this.t('输入标题', 'Enter title'), text: this.editItemTitle })
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding(this.fontSize * 0.8)
              .onChange((value: string) => {
                this.editItemTitle = value;
              });
          }

          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('正面内容', 'Front Content'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            TextArea({ placeholder: this.t('输入正面内容（问题或提示）', 'Enter front content (question or prompt)'), text: this.editItemContent })
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding(this.fontSize * 0.8)
              .height(this.fontSize * 6)
              .onChange((value: string) => {
                this.editItemContent = value;
              });
          }

          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('背面内容（答案）', 'Back Content (Answer)'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            TextArea({ placeholder: this.t('输入背面内容（答案或解释）', 'Enter back content (answer or explanation)'), text: this.editItemAnswer })
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding(this.fontSize * 0.8)
              .height(this.fontSize * 6)
              .onChange((value: string) => {
                this.editItemAnswer = value;
              });
          }

          // 删除按钮（仅编辑模式）
          if (this.isEditing && this.selectedItem) {
            Button(this.t('删除项目', 'Delete Item'))
              .width('100%')
              .fontSize(this.fontSize)
              .fontColor('#EF4444')
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding({ top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
              .margin({ top: this.fontSize * 2 })
              .onClick(() => {
                this.showDeleteItemConfirm();
              });
          }
        }
        .width('100%');
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  @Builder
  private ShareView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      // 标题栏
      Row() {
        Text('\uf053') // chevron-left
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode(this.selectedList ? 'items' : 'lists');
          });

        Text(this.selectedList ? this.t('分享清单', 'Share List') : this.t('导入清单', 'Import List'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Blank().width(this.fontSize + this.iconButtonPadding() * 2);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
        Column({ space: this.fontSize * 1.5 }) {
          if (this.selectedList) {
            // 分享功能
            Column({ space: this.fontSize }) {
              Text(this.t('生成分享链接', 'Generate Share Link'))
                .fontSize(this.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textColor);

              Text(
                this.t(
                  '将清单（可选加密）上传并生成短链接；对方可在“导入清单”中粘贴链接导入。',
                  'Uploads (optionally encrypted) and returns a short link. Paste it in “Import List” to import.',
                ),
              )
                .fontSize(this.fontSize * 0.8)
                .fontColor(this.theme.mutedTextColor)
                .opacity(0.85);

              Column({ space: this.fontSize * 0.3 }) {
                Text(this.t('加密密码（可选）', 'Encryption Password (optional)'))
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.theme.mutedTextColor);

                TextInput({ placeholder: this.t('设置密码保护分享内容', 'Set password to protect shared content'), text: this.sharePassword })
                  .fontSize(this.fontSize)
                  .fontColor(this.theme.textColor)
                  .backgroundColor(this.theme.surfaceBackgroundColor)
                  .borderRadius(this.fontSize * 0.5)
                  .padding(this.fontSize * 0.8)
                  .type(InputType.Password)
                  .onChange((value: string) => {
                    this.sharePassword = value;
                  });
              }

              Button(this.t('上传并生成链接', 'Upload & Generate'))
                .width('100%')
                .fontSize(this.fontSize)
                .fontColor(this.theme.chipSelectedTextColor)
                .backgroundColor(this.theme.accentColor)
                .borderRadius(this.fontSize * 0.5)
                .padding({ top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
                .enabled(!this.shareUploading)
                .opacity(this.shareUploading ? 0.7 : 1)
                .onClick(() => this.generateShareLink());

              if (this.shareError) {
                Text(this.shareError)
                  .fontSize(this.fontSize * 0.85)
                  .fontColor('#EF4444');
              }

              if (this.shareLink) {
                Column({ space: this.fontSize * 0.5 }) {
                  Text(this.t('已上传并生成分享链接', 'Share link ready'))
                    .fontSize(this.fontSize * 0.9)
                    .fontColor(this.theme.accentColor);

                  Text(this.shareLink)
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.mutedTextColor)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding(this.fontSize * 0.5)
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .borderRadius(this.fontSize * 0.3)
                    .width('100%');

                  Button(this.shareCopied ? this.t('已复制', 'Copied!') : this.t('复制链接', 'Copy Link'))
                    .width('100%')
                    .fontSize(this.fontSize)
                    .fontColor(this.shareCopied ? this.theme.accentColor : this.theme.chipTextColor)
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .borderRadius(this.fontSize * 0.5)
                    .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                    .onClick(() => this.copyShareLink());
                }
                .width('100%')
                .padding(this.fontSize * 0.8)
                .backgroundColor(this.theme.surfaceMutedBackgroundColor)
                .borderRadius(this.fontSize * 0.5);
              }
            }
            .width('100%');

            Divider()
              .color(this.theme.borderColor)
              .strokeWidth(1);
          }

          // 导入功能
          Column({ space: this.fontSize }) {
            Text(this.t('从链接导入', 'Import from Link'))
              .fontSize(this.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.textColor);

            Column({ space: this.fontSize * 0.3 }) {
              Text(this.t('分享链接', 'Share Link'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.mutedTextColor);

              TextArea({ placeholder: this.t('粘贴分享链接', 'Paste share link'), text: this.importData })
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.textColor)
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .padding(this.fontSize * 0.8)
                .height(this.fontSize * 5)
                .onChange((value: string) => {
                  this.importData = value;
                });
            }

            Column({ space: this.fontSize * 0.3 }) {
              Text(this.t('密码（如有）', 'Password (if any)'))
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.mutedTextColor);

              TextInput({ placeholder: this.t('输入密码', 'Enter password'), text: this.importPassword })
                .fontSize(this.fontSize)
                .fontColor(this.theme.textColor)
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .padding(this.fontSize * 0.8)
                .type(InputType.Password)
                .onChange((value: string) => {
                  this.importPassword = value;
                });
            }

            if (this.importError) {
              Text(this.importError)
                .fontSize(this.fontSize * 0.85)
                .fontColor('#EF4444');
            }

            Button(this.t('导入', 'Import'))
              .width('100%')
              .fontSize(this.fontSize)
              .fontColor(this.theme.chipSelectedTextColor)
              .backgroundColor(this.theme.accentColor)
              .borderRadius(this.fontSize * 0.5)
              .padding({ top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
              .enabled(this.importData.trim().length > 0)
              .opacity(this.importData.trim().length > 0 ? 1 : 0.5)
              .onClick(() => this.importFromData());
          }
          .width('100%');
        }
        .width('100%');
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  build() {
    Stack() {
      if (this.viewMode === 'lists') {
        this.ListsView();
      } else if (this.viewMode === 'items') {
        this.ItemsView();
      } else if (this.viewMode === 'review') {
        this.ReviewView();
      } else if (this.viewMode === 'edit-list') {
        this.EditListView();
      } else if (this.viewMode === 'edit-item') {
        this.EditItemView();
      } else if (this.viewMode === 'share') {
        this.ShareView();
      }
    }
    .onAppear(() => setCustomListBackHandler((): boolean => this.handleBackPress()))
    .onDisAppear(() => clearCustomListBackHandler())
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }
}
