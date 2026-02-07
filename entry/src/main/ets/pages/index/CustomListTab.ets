// 自定义清单Tab组件 - 记忆表格模式

import type { AppThemeTokens } from '../../common/appTheme';
import type { ReferenceLang } from '../../common/referenceModels';
import type {
  CustomList,
  CustomListCollection,
  ReviewStats,
  ReviewGrade,
  ListSection,
  MemoryTable,
  MemoryTableRow,
  MemoryTableCell,
} from '../../common/customListModels';
import {
  createCustomList,
  createListSection,
  createMemoryTable,
  createTableRow,
  getDueRows,
  calculateReviewStats,
  listToMarkdown,
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

type ViewMode = 'lists' | 'sections' | 'edit-list' | 'edit-section' | 'edit-table' | 'review' | 'share';

const FONT_AWESOME_SOLID_FAMILY: string = 'FontAwesomeSolid';

interface ReviewItem {
  sectionId: string;
  tableId: string;
  row: MemoryTableRow;
  headers: Array<string>;
}

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
  @State private selectedSection: ListSection | null = null;
  @State private selectedTable: MemoryTable | null = null;
  @State private reviewItems: Array<ReviewItem> = [];
  @State private currentReviewIndex: number = 0;
  @State private showAnswer: boolean = false;
  @State private reviewStats: ReviewStats | null = null;
  @State private showTableSectionPicker: boolean = false;

  // 编辑表单状态
  @State private editListName: string = '';
  @State private editListDesc: string = '';
  @State private editSectionTitle: string = '';
  @State private editSectionContent: string = '';
  @State private editSectionLevel: number = 2;
  @State private isEditing: boolean = false;

  // 表格编辑状态
  @State private editHeaders: Array<string> = [];
  @State private editRows: Array<Array<string>> = [];
  @State private editRowIds: Array<string> = [];

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

    const oldReminderEnabled = this.selectedList.reminderEnabled;
    const oldCalendarEventId = this.selectedList.calendarEventId;
    let newCalendarEventId: string | undefined = oldCalendarEventId;

    if (this.reminderEnabled && !oldReminderEnabled) {
      const reminderId = await createDailyReminder({
        listId: this.selectedList.id,
        listName: this.editListName.trim(),
        hour: this.reminderHour,
        minute: this.reminderMinute,
      });
      newCalendarEventId = reminderId.toString();
    } else if (!this.reminderEnabled && oldReminderEnabled && oldCalendarEventId) {
      await cancelReminder(parseInt(oldCalendarEventId));
      newCalendarEventId = undefined;
    } else if (this.reminderEnabled && oldReminderEnabled && oldCalendarEventId) {
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
    this.setViewMode(this.selectedList ? 'sections' : 'lists');
    this.onRefreshLists?.();
  }

  private async deleteList(listId: string): Promise<void> {
    const ctx = this.getHostContext();
    if (!ctx) return;

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

  private async createNewSection(): Promise<void> {
    if (!this.selectedList || !this.editSectionTitle.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const newSection = createListSection(this.editSectionTitle.trim(), this.editSectionLevel);
    newSection.content = this.editSectionContent.trim();

    const updatedList = await this.repository.addSection(ctx, this.selectedList.id, newSection);
    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }

    this.editSectionTitle = '';
    this.editSectionContent = '';
    this.editSectionLevel = 2;
    this.setViewMode('sections');
    this.onRefreshLists?.();
  }

  private async updateSelectedSection(): Promise<void> {
    if (!this.selectedList || !this.selectedSection || !this.editSectionTitle.trim()) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.updateSection(ctx, this.selectedList.id, this.selectedSection.id, {
      title: this.editSectionTitle.trim(),
      content: this.editSectionContent.trim(),
      level: this.editSectionLevel,
    });

    if (updatedList) {
      this.selectedList = updatedList;
      this.selectedSection = updatedList.sections.find(s => s.id === this.selectedSection?.id) || null;
      await this.loadLists();
    }

    this.setViewMode('sections');
    this.onRefreshLists?.();
  }

  private async deleteSection(sectionId: string): Promise<void> {
    if (!this.selectedList) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.deleteSection(ctx, this.selectedList.id, sectionId);
    if (updatedList) {
      this.selectedList = updatedList;
      await this.loadLists();
    }
    this.onRefreshLists?.();
  }

  private async createNewTable(): Promise<void> {
    if (!this.selectedList || !this.selectedSection) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const headers = this.editHeaders.filter(h => h.trim() !== '');
    if (headers.length < 2) {
      headers.push('');
      headers.push('');
    }

    const newTable = createMemoryTable(headers);

    for (let i = 0; i < this.editRows.length; i++) {
      const rowCells = this.editRows[i];
      const cellTexts: Array<string> = [];
      for (let j = 0; j < headers.length; j++) {
        cellTexts.push(rowCells[j] || '');
      }
      if (cellTexts.some(c => c.trim() !== '')) {
        newTable.rows.push(createTableRow(cellTexts));
      }
    }

    const updatedList = await this.repository.addTable(ctx, this.selectedList.id, this.selectedSection.id, newTable);
    if (updatedList) {
      this.selectedList = updatedList;
      this.selectedSection = updatedList.sections.find(s => s.id === this.selectedSection?.id) || null;
      await this.loadLists();
    }

    this.resetTableEditState();
    this.setViewMode('sections');
    this.onRefreshLists?.();
  }

  private async updateSelectedTable(): Promise<void> {
    if (!this.selectedList || !this.selectedSection || !this.selectedTable) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const headers = this.editHeaders.filter(h => h.trim() !== '');
    if (headers.length < 2) {
      headers.push('');
      headers.push('');
    }

    const newRows: Array<MemoryTableRow> = [];
    for (let i = 0; i < this.editRows.length; i++) {
      const rowCells = this.editRows[i];
      const cellObjs: Array<MemoryTableCell> = [];
      for (let j = 0; j < headers.length; j++) {
        cellObjs.push({ text: rowCells[j] || '' });
      }
      if (cellObjs.some(c => c.text.trim() !== '')) {
        const existingRow = this.selectedTable.rows.find(r => r.id === this.editRowIds[i]);
        if (existingRow) {
          newRows.push({
            id: existingRow.id,
            cells: cellObjs,
            reviewCount: existingRow.reviewCount,
            lastReviewAt: existingRow.lastReviewAt,
            nextReviewAt: existingRow.nextReviewAt,
            easeFactor: existingRow.easeFactor,
            interval: existingRow.interval,
            lastGrade: existingRow.lastGrade,
          });
        } else {
          newRows.push(createTableRow(cellObjs.map(c => c.text)));
        }
      }
    }

    const updatedList = await this.repository.updateTable(
      ctx,
      this.selectedList.id,
      this.selectedSection.id,
      this.selectedTable.id,
      { headers, rows: newRows }
    );

    if (updatedList) {
      this.selectedList = updatedList;
      this.selectedSection = updatedList.sections.find(s => s.id === this.selectedSection?.id) || null;
      this.selectedTable = this.selectedSection?.tables.find(t => t.id === this.selectedTable?.id) || null;
      await this.loadLists();
    }

    this.setViewMode('sections');
    this.onRefreshLists?.();
  }

  private async deleteTable(tableId: string): Promise<void> {
    if (!this.selectedList || !this.selectedSection) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.deleteTable(ctx, this.selectedList.id, this.selectedSection.id, tableId);
    if (updatedList) {
      this.selectedList = updatedList;
      this.selectedSection = updatedList.sections.find(s => s.id === this.selectedSection?.id) || null;
      await this.loadLists();
    }
    this.onRefreshLists?.();
  }

  private resetTableEditState(): void {
    this.editHeaders = ['', ''];
    this.editRows = [['', '']];
    this.editRowIds = [''];
    this.selectedTable = null;
    this.isEditing = false;
  }

  private initTableEditState(table: MemoryTable): void {
    this.editHeaders = table.headers.slice();
    this.editRows = [];
    this.editRowIds = [];

    for (const row of table.rows) {
      const cells: Array<string> = [];
      for (let i = 0; i < table.headers.length; i++) {
        cells.push(row.cells[i]?.text || '');
      }
      this.editRows.push(cells);
      this.editRowIds.push(row.id);
    }

    if (this.editRows.length === 0) {
      const emptyRow: Array<string> = [];
      for (let i = 0; i < this.editHeaders.length; i++) {
        emptyRow.push('');
      }
      this.editRows.push(emptyRow);
      this.editRowIds.push('');
    }
  }

  private openTableEditor(section: ListSection, table?: MemoryTable): void {
    this.selectedSection = section;
    if (table) {
      this.selectedTable = table;
      this.initTableEditState(table);
      this.isEditing = true;
    } else {
      this.resetTableEditState();
    }
    this.showTableSectionPicker = false;
    this.setViewMode('edit-table');
  }

  private addTableColumn(): void {
    this.editHeaders.push('');
    for (let i = 0; i < this.editRows.length; i++) {
      this.editRows[i].push('');
    }
    // 触发响应式更新
    this.editHeaders = this.editHeaders.slice();
    this.editRows = this.editRows.slice();
  }

  private removeTableColumn(index: number): void {
    if (this.editHeaders.length <= 2) return;
    this.editHeaders.splice(index, 1);
    for (let i = 0; i < this.editRows.length; i++) {
      this.editRows[i].splice(index, 1);
    }
    this.editHeaders = this.editHeaders.slice();
    this.editRows = this.editRows.slice();
  }

  private addTableRow(): void {
    const newRow: Array<string> = [];
    for (let i = 0; i < this.editHeaders.length; i++) {
      newRow.push('');
    }
    this.editRows.push(newRow);
    this.editRowIds.push('');
    this.editRows = this.editRows.slice();
    this.editRowIds = this.editRowIds.slice();
  }

  private removeTableRow(index: number): void {
    if (this.editRows.length <= 1) return;
    this.editRows.splice(index, 1);
    this.editRowIds.splice(index, 1);
    this.editRows = this.editRows.slice();
    this.editRowIds = this.editRowIds.slice();
  }

  private startReview(): void {
    if (!this.selectedList) return;

    const dueRows = getDueRows(this.selectedList);
    if (dueRows.length === 0) return;

    this.reviewItems = [];
    for (const item of dueRows) {
      const section = this.selectedList.sections.find(s => s.id === item.sectionId);
      const table = section?.tables.find(t => t.id === item.tableId);
      if (table) {
        this.reviewItems.push({
          sectionId: item.sectionId,
          tableId: item.tableId,
          row: item.row,
          headers: table.headers,
        });
      }
    }

    this.currentReviewIndex = 0;
    this.showAnswer = false;
    this.setViewMode('review');
  }

  private async recordReviewResult(grade: ReviewGrade): Promise<void> {
    if (!this.selectedList || this.currentReviewIndex >= this.reviewItems.length) return;
    const ctx = this.getHostContext();
    if (!ctx) return;

    const currentItem = this.reviewItems[this.currentReviewIndex];
    await this.repository.recordReview(
      ctx,
      this.selectedList.id,
      currentItem.sectionId,
      currentItem.tableId,
      currentItem.row.id,
      grade
    );

    const updatedList = await this.repository.getList(ctx, this.selectedList.id);
    if (updatedList) {
      this.selectedList = updatedList;
      this.reviewStats = calculateReviewStats(updatedList);
      await this.loadLists();
    }

    this.currentReviewIndex++;
    this.showAnswer = false;

    if (this.currentReviewIndex >= this.reviewItems.length) {
      this.setViewMode('sections');
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

  private async copyMarkdown(): Promise<void> {
    if (!this.selectedList) return;

    const markdown = listToMarkdown(this.selectedList);
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, markdown);
    const board = pasteboard.getSystemPasteboard();
    try {
      await board.setData(pasteData);
      promptAction.showToast({ message: this.t('已复制Markdown', 'Markdown copied') });
    } catch (_) {
      // ignore
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

  private getTotalRows(list: CustomList): number {
    let count = 0;
    for (const section of list.sections) {
      for (const table of section.tables) {
        count += table.rows.length;
      }
    }
    return count;
  }

  private setViewMode(next: ViewMode): void {
    if (this.viewMode === next) return;
    this.showTableSectionPicker = false;
    this.viewMode = next;
  }

  private iconButtonPadding(): number {
    return this.fontSize * 0.6;
  }

  private handleBackPress(): boolean {
    if (this.viewMode === 'sections') {
      this.selectedList = null;
      this.selectedSection = null;
      this.setViewMode('lists');
      return true;
    }
    if (this.viewMode === 'review') {
      this.setViewMode('sections');
      return true;
    }
    if (this.viewMode === 'share') {
      this.setViewMode(this.selectedList ? 'sections' : 'lists');
      return true;
    }
    if (this.viewMode === 'edit-list') {
      this.setViewMode(this.isEditing && this.selectedList ? 'sections' : 'lists');
      return true;
    }
    if (this.viewMode === 'edit-section') {
      this.setViewMode('sections');
      return true;
    }
    if (this.viewMode === 'edit-table') {
      this.resetTableEditState();
      this.setViewMode('sections');
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
      // ignore
    }
  }

  private async showDeleteSectionConfirm(sectionId: string): Promise<void> {
    try {
      const result: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: this.t('确认删除', 'Confirm Delete'),
        message: this.t('删除章节将同时删除其中的所有表格，确定要删除吗？', 'Deleting this section will also delete all tables in it. Are you sure?'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.theme.mutedTextColor.toString() },
          { text: this.t('删除', 'Delete'), color: '#EF4444' },
        ],
      });
      if (result.index === 1) {
        await this.deleteSection(sectionId);
      }
    } catch (_) {
      // ignore
    }
  }

  private async showDeleteTableConfirm(tableId: string): Promise<void> {
    try {
      const result: promptAction.ShowDialogSuccessResponse = await promptAction.showDialog({
        title: this.t('确认删除', 'Confirm Delete'),
        message: this.t('删除后无法恢复，确定要删除吗？', 'This action cannot be undone. Are you sure?'),
        buttons: [
          { text: this.t('取消', 'Cancel'), color: this.theme.mutedTextColor.toString() },
          { text: this.t('删除', 'Delete'), color: '#EF4444' },
        ],
      });
      if (result.index === 1) {
        await this.deleteTable(tableId);
      }
    } catch (_) {
      // ignore
    }
  }

  @Builder
  private ListsView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text(this.t('我的清单', 'My Lists'))
          .fontSize(this.fontSize * 1.25)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.accentColor)
          .onAreaChange((_: Area, area: Area) => {
            this.onTitleAreaHeightChange?.(lengthToNumber(area.height));
          });

        Row({ space: this.fontSize * 0.5 }) {
          Text('\uf56f')
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

          Text('\uf067')
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
        Column({ space: this.fontSize }) {
          Text('\uf0ca')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 3)
            .fontColor(this.theme.mutedTextColor);

          Text(this.t('暂无清单', 'No lists yet'))
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor);

          Text(this.t('点击右上角 + 创建记忆表格', 'Tap + to create a memory table'))
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.mutedTextColor);
        }
        .width('100%')
        .padding({ top: this.fontSize * 4 })
        .alignItems(HorizontalAlign.Center);
      } else {
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
                    Text('\uf1e0')
                      .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                      .fontSize(this.fontSize * 0.8)
                      .fontColor(this.theme.accentColor)
                      .margin({ right: this.fontSize * 0.5 });
                  }

                  Text('\uf105')
                    .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                    .fontSize(this.fontSize)
                    .fontColor(this.theme.mutedTextColor);
                }
                .width('100%')
                .alignItems(VerticalAlign.Center);

                Row({ space: this.fontSize * 0.8 }) {
                  Text(this.t(`${list.sections.length} 章节`, `${list.sections.length} sections`))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor);

                  Text(this.t(`${this.getTotalRows(list)} 行`, `${this.getTotalRows(list)} rows`))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor);

                  if (this.getTotalRows(list) > 0) {
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
                this.reviewStats = this.getTotalRows(list) > 0 ? calculateReviewStats(list) : null;
                this.setViewMode('sections');
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
    if (this.getTotalRows(list) > 0) {
      Text(this.getDueCountText(list))
        .fontSize(this.fontSize * 0.8)
        .fontColor(this.theme.accentColor)
        .fontWeight(FontWeight.Medium)
        .visibility(this.hasDueRows(list) ? Visibility.Visible : Visibility.Hidden);
    }
  }

  private getDueCountText(list: CustomList): string {
    const stats = calculateReviewStats(list);
    return this.t(`${stats.dueCount} 待复习`, `${stats.dueCount} due`);
  }

  private hasDueRows(list: CustomList): boolean {
    const stats = calculateReviewStats(list);
    return stats.dueCount > 0;
  }

  @Builder
  private SectionsView(): void {
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
        Row() {
          Row({ space: this.fontSize * 0.5 }) {
            Text('\uf053')
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
            Text('\uf1e0')
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

            Text('\uf013')
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
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Row({ space: this.fontSize * 0.5 }) {
          Button(this.t('æ–°å»ºç« èŠ‚', 'New Section'))
            .layoutWeight(1)
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.chipSelectedTextColor)
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.6)
            .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
            .margin({ right: this.fontSize * 0.3 })
            .onClick(() => {
              this.editSectionTitle = '';
              this.editSectionContent = '';
              this.editSectionLevel = 2;
              this.selectedSection = null;
              this.isEditing = false;
              this.setViewMode('edit-section');
            });

          Button(this.t('æ–°å»ºè¡¨æ ¼', 'New Table'))
            .layoutWeight(1)
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.textColor)
            .backgroundColor(this.theme.surfaceBackgroundColor)
            .borderRadius(this.fontSize * 0.6)
            .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
            .enabled(this.selectedList.sections.length > 0)
            .opacity(this.selectedList.sections.length > 0 ? 1 : 0.5)
            .onClick(() => {
              if (!this.selectedList || this.selectedList.sections.length === 0) {
                promptAction.showToast({ message: this.t('è¯·é¦–å…ˆæ·»åŠ ä¸€ä¸ªç« èŠ‚', 'Add a section first') });
                return;
              }
              this.showTableSectionPicker = true;
            });
        }
        .width('100%')
        .margin({ top: this.fontSize * 0.6 });

        if (this.showTableSectionPicker && this.selectedList) {
          Column({ space: this.fontSize * 0.4 }) {
            Text(this.t('é€‰æ‹©ä¸€ä¸ªç« èŠ‚ç»æ–°è¡¨æ ¼', 'Pick a section to add a table'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.mutedTextColor);

            ForEach(this.selectedList.sections, (section: ListSection) => {
              Button(section.title || this.t('æœªå‘½åç« èŠ‚', 'Untitled section'))
                .width('100%')
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.textColor)
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .padding({ top: this.fontSize * 0.65, bottom: this.fontSize * 0.65 })
                .onClick(() => this.openTableEditor(section));
            }, (section: ListSection) => section.id);

            Button(this.t('å–æ¶ˆ', 'Cancel'))
              .width('100%')
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.mutedTextColor)
              .backgroundColor(this.theme.surfaceMutedBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding({ top: this.fontSize * 0.65, bottom: this.fontSize * 0.65 })
              .onClick(() => {
                this.showTableSectionPicker = false;
              });
          }
          .width('100%')
          .padding(this.fontSize * 0.6)
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .borderRadius(this.fontSize * 0.6)
          .margin({ top: this.fontSize * 0.6 });
        }

        if (this.reviewStats && this.getTotalRows(this.selectedList) > 0) {
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

        if (this.selectedList.sections.length === 0) {
          Column({ space: this.fontSize }) {
            Text('\uf0ca')
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize * 3)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('暂无章节', 'No sections yet'))
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('点击右上角 + 添加第一个章节', 'Tap + to add your first section'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.mutedTextColor);
          }
          .width('100%')
          .padding({ top: this.fontSize * 4 })
          .alignItems(HorizontalAlign.Center);
        } else {
          Scroll(this.scroller) {
            Column({ space: this.fontSize * 0.8 }) {
              ForEach(this.selectedList.sections, (section: ListSection) => {
                this.SectionCard(section);
              }, (section: ListSection) => section.id);
            }
            .width('100%');
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off);
        }
      }
      .width('100%')
      .height('100%')
      .padding(this.tabPadding());
    }
  }

  @Builder
  private SectionCard(section: ListSection): void {
    Column({ space: this.fontSize * 0.5 }) {
      Row() {
        Text('#'.repeat(section.level) + ' ' + section.title)
          .fontSize(this.fontSize * 0.95)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row({ space: this.fontSize * 0.3 }) {
          Text('\uf044')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.mutedTextColor)
            .padding(this.fontSize * 0.3)
            .onClick(() => {
              this.selectedSection = section;
              this.editSectionTitle = section.title;
              this.editSectionContent = section.content;
              this.editSectionLevel = section.level;
              this.isEditing = true;
              this.setViewMode('edit-section');
            });

          Text('\uf1c9')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.accentColor)
            .padding(this.fontSize * 0.3)
            .onClick(() => this.openTableEditor(section));

          Text('\uf2ed')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 0.85)
            .fontColor('#EF4444')
            .padding(this.fontSize * 0.3)
            .onClick(() => this.showDeleteSectionConfirm(section.id));
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (section.content) {
        Text(section.content)
          .fontSize(this.fontSize * 0.8)
          .fontColor(this.theme.mutedTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }

      if (section.tables.length > 0) {
        ForEach(section.tables, (table: MemoryTable) => {
          this.TablePreview(section, table);
        }, (table: MemoryTable) => table.id);
      }
    }
    .width('100%')
    .padding(this.fontSize * 0.8)
    .backgroundColor(this.theme.surfaceBackgroundColor)
    .borderRadius(this.fontSize * 0.5);
  }

  @Builder
  private TablePreview(section: ListSection, table: MemoryTable): void {
    Column({ space: this.fontSize * 0.3 }) {
      Row() {
        Text(this.t(`表格 (${table.rows.length} 行)`, `Table (${table.rows.length} rows)`))
          .fontSize(this.fontSize * 0.8)
          .fontColor(this.theme.mutedTextColor);

        Row({ space: this.fontSize * 0.2 }) {
          Text('\uf044')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 0.75)
            .fontColor(this.theme.mutedTextColor)
            .padding(this.fontSize * 0.2)
            .onClick(() => this.openTableEditor(section, table));

          Text('\uf2ed')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize * 0.75)
            .fontColor('#EF4444')
            .padding(this.fontSize * 0.2)
            .onClick(() => this.showDeleteTableConfirm(table.id));
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center);

      if (table.headers.length > 0) {
        Row() {
          ForEach(table.headers.slice(0, 3), (header: string, index: number) => {
            Text(header || '-')
              .fontSize(this.fontSize * 0.75)
              .fontColor(this.theme.mutedTextColor)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);

            if (index < 2 && index < table.headers.length - 1) {
              Text('|')
                .fontSize(this.fontSize * 0.75)
                .fontColor(this.theme.borderColor)
                .margin({ left: this.fontSize * 0.3, right: this.fontSize * 0.3 });
            }
          }, (header: string, index: number) => `${header}-${index}`);

          if (table.headers.length > 3) {
            Text('...')
              .fontSize(this.fontSize * 0.75)
              .fontColor(this.theme.mutedTextColor);
          }
        }
        .width('100%')
        .padding({ top: this.fontSize * 0.2, bottom: this.fontSize * 0.2 })
        .backgroundColor(this.theme.surfaceMutedBackgroundColor)
        .borderRadius(this.fontSize * 0.25);
      }
    }
    .width('100%')
    .margin({ top: this.fontSize * 0.3 })
    .padding(this.fontSize * 0.5)
    .backgroundColor(this.theme.surfaceMutedBackgroundColor)
    .borderRadius(this.fontSize * 0.3);
  }

  @Builder
  private EditListView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text('\uf053')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode(this.selectedList ? 'sections' : 'lists');
          });

        Text(this.isEditing ? this.t('编辑清单', 'Edit List') : this.t('新建清单', 'New List'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Text('\uf00c')
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
  private EditSectionView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text('\uf053')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode('sections');
          });

        Text(this.isEditing ? this.t('编辑章节', 'Edit Section') : this.t('新建章节', 'New Section'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Text('\uf00c')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.editSectionTitle.trim() ? this.theme.accentColor : this.theme.mutedTextColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            if (this.isEditing) {
              this.updateSelectedSection();
            } else {
              this.createNewSection();
            }
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
        Column({ space: this.fontSize }) {
          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('标题级别', 'Heading Level'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            Row({ space: this.fontSize * 0.5 }) {
              ForEach([2, 3, 4, 5, 6] as Array<number>, (level: number) => {
                Text(`H${level}`)
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.editSectionLevel === level ? this.theme.chipSelectedTextColor : this.theme.textColor)
                  .backgroundColor(this.editSectionLevel === level ? this.theme.accentColor : this.theme.surfaceBackgroundColor)
                  .borderRadius(this.fontSize * 0.3)
                  .padding({ left: this.fontSize * 0.6, right: this.fontSize * 0.6, top: this.fontSize * 0.3, bottom: this.fontSize * 0.3 })
                  .onClick(() => {
                    this.editSectionLevel = level;
                  });
              }, (level: number) => level.toString());
            }
          }

          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('标题', 'Title'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            TextInput({ placeholder: this.t('输入章节标题', 'Enter section title'), text: this.editSectionTitle })
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding(this.fontSize * 0.8)
              .onChange((value: string) => {
                this.editSectionTitle = value;
              });
          }

          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('描述（可选）', 'Description (optional)'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            TextArea({ placeholder: this.t('输入章节描述', 'Enter section description'), text: this.editSectionContent })
              .fontSize(this.fontSize)
              .fontColor(this.theme.textColor)
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.5)
              .padding(this.fontSize * 0.8)
              .height(this.fontSize * 5)
              .onChange((value: string) => {
                this.editSectionContent = value;
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
  private EditTableView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text('\uf053')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.resetTableEditState();
            this.setViewMode('sections');
          });

        Text(this.isEditing ? this.t('编辑表格', 'Edit Table') : this.t('新建表格', 'New Table'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Text('\uf00c')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            if (this.isEditing) {
              this.updateSelectedTable();
            } else {
              this.createNewTable();
            }
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
        Column({ space: this.fontSize }) {
          Column({ space: this.fontSize * 0.3 }) {
            Row() {
              Text(this.t('表头', 'Headers'))
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.mutedTextColor);

              Text('\uf067')
                .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.accentColor)
                .padding(this.fontSize * 0.3)
                .onClick(() => this.addTableColumn());
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center);

            Row({ space: this.fontSize * 0.3 }) {
              ForEach(this.editHeaders, (header: string, index: number) => {
                Row() {
                  TextInput({ placeholder: this.t(`列${index + 1}`, `Col${index + 1}`), text: header })
                    .fontSize(this.fontSize * 0.9)
                    .fontColor(this.theme.textColor)
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .borderRadius(this.fontSize * 0.3)
                    .padding(this.fontSize * 0.5)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.editHeaders[index] = value;
                      this.editHeaders = this.editHeaders.slice();
                    });

                  if (this.editHeaders.length > 2) {
                    Text('\uf00d')
                      .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                      .fontSize(this.fontSize * 0.75)
                      .fontColor('#EF4444')
                      .padding(this.fontSize * 0.2)
                      .onClick(() => this.removeTableColumn(index));
                  }
                }
                .layoutWeight(1);
              }, (header: string, index: number) => `header-${index}-${this.editHeaders.length}`);
            }
            .width('100%');
          }

          Column({ space: this.fontSize * 0.3 }) {
            Row() {
              Text(this.t('数据行', 'Rows'))
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.mutedTextColor);

              Text('\uf067')
                .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.accentColor)
                .padding(this.fontSize * 0.3)
                .onClick(() => this.addTableRow());
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center);

            ForEach(this.editRows, (row: Array<string>, rowIndex: number) => {
              Row({ space: this.fontSize * 0.3 }) {
                ForEach(row, (cell: string, colIndex: number) => {
                  TextInput({ placeholder: '...', text: cell })
                    .fontSize(this.fontSize * 0.85)
                    .fontColor(this.theme.textColor)
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .borderRadius(this.fontSize * 0.3)
                    .padding(this.fontSize * 0.4)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.editRows[rowIndex][colIndex] = value;
                      this.editRows = this.editRows.slice();
                    });
                }, (cell: string, colIndex: number) => `cell-${rowIndex}-${colIndex}-${this.editRows.length}`);

                if (this.editRows.length > 1) {
                  Text('\uf00d')
                    .fontFamily(FONT_AWESOME_SOLID_FAMILY)
                    .fontSize(this.fontSize * 0.75)
                    .fontColor('#EF4444')
                    .padding(this.fontSize * 0.2)
                    .onClick(() => this.removeTableRow(rowIndex));
                }
              }
              .width('100%')
              .margin({ bottom: this.fontSize * 0.3 });
            }, (row: Array<string>, rowIndex: number) => `row-${rowIndex}-${this.editRows.length}`);
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
        Row() {
          Text(`${this.currentReviewIndex + 1} / ${this.reviewItems.length}`)
            .fontSize(this.fontSize * 0.9)
            .fontColor(this.theme.mutedTextColor);

          Text('\uf00d')
            .fontFamily(FONT_AWESOME_SOLID_FAMILY)
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor)
            .padding(this.fontSize * 0.5)
            .onClick(() => {
              this.setViewMode('sections');
            });
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center);

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

        Column({ space: this.fontSize }) {
          Column({ space: this.fontSize * 0.5 }) {
            if (this.currentReviewIndex < this.reviewItems.length) {
              this.ReviewCardContent();
            }
          }
          .width('100%')
          .padding(this.fontSize * 1.5)
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .borderRadius(this.fontSize * 0.8);

          if (this.showAnswer && this.currentReviewIndex < this.reviewItems.length) {
            Column() {
              this.ReviewAnswerContent();
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

  @Builder
  private ReviewCardContent(): void {
    Column({ space: this.fontSize * 0.3 }) {
      if (this.reviewItems[this.currentReviewIndex].headers[0]) {
        Text(this.reviewItems[this.currentReviewIndex].headers[0])
          .fontSize(this.fontSize * 0.8)
          .fontColor(this.theme.mutedTextColor);
      }

      Text(this.reviewItems[this.currentReviewIndex].row.cells[0]?.text || '')
        .fontSize(this.fontSize * 1.2)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.textColor)
        .textAlign(TextAlign.Center);
    }
  }

  @Builder
  private ReviewAnswerContent(): void {
    Column({ space: this.fontSize * 0.5 }) {
      ForEach(this.reviewItems[this.currentReviewIndex].headers.slice(1), (header: string, index: number) => {
        Column({ space: this.fontSize * 0.2 }) {
          Text(header || this.t(`列${index + 2}`, `Col${index + 2}`))
            .fontSize(this.fontSize * 0.8)
            .fontColor(this.theme.mutedTextColor);

          Text(this.reviewItems[this.currentReviewIndex].row.cells[index + 1]?.text || '-')
            .fontSize(this.fontSize)
            .fontColor(this.theme.textColor);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);
      }, (header: string, index: number) => `answer-${index}`);
    }
  }

  private getProgressIndicators(): Array<number> {
    const result: Array<number> = [];
    for (let i = 0; i < this.reviewItems.length; i++) {
      result.push(i);
    }
    return result;
  }

  @Builder
  private ShareView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text('\uf053')
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding(this.iconButtonPadding())
          .borderRadius(this.iconButtonPadding())
          .onClick(() => {
            this.setViewMode(this.selectedList ? 'sections' : 'lists');
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
            Column({ space: this.fontSize }) {
              Text(this.t('分享为Markdown', 'Share as Markdown'))
                .fontSize(this.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.textColor);

              Text(this.t(
                '清单将转换为Markdown格式上传。对方可通过链接导入。',
                'List will be converted to Markdown format and uploaded. Others can import via the link.',
              ))
                .fontSize(this.fontSize * 0.8)
                .fontColor(this.theme.mutedTextColor);

              Button(this.t('复制Markdown', 'Copy Markdown'))
                .width('100%')
                .fontSize(this.fontSize)
                .fontColor(this.theme.chipTextColor)
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .padding({ top: this.fontSize * 0.7, bottom: this.fontSize * 0.7 })
                .onClick(() => this.copyMarkdown());

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
                  Text(this.t('分享链接已生成', 'Share link ready'))
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
      } else if (this.viewMode === 'sections') {
        this.SectionsView();
      } else if (this.viewMode === 'review') {
        this.ReviewView();
      } else if (this.viewMode === 'edit-list') {
        this.EditListView();
      } else if (this.viewMode === 'edit-section') {
        this.EditSectionView();
      } else if (this.viewMode === 'edit-table') {
        this.EditTableView();
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
