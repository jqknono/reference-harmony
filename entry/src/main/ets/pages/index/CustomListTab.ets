// 自定义清单Tab组件 - 记忆表格模式

import type { AppThemeTokens } from '../../common/appTheme';
import type { ReferenceLang } from '../../common/referenceModels';
import type {
  CustomList,
  CustomListCollection,
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
  listToMarkdown,
} from '../../common/customListModels';
import { CustomListRepository } from '../../common/customListRepository';
import { clearCustomListBackHandler, setCustomListBackHandler } from '../../common/backHandlerRegistry';
import { lengthToNumber } from './utils';
import { HIDE_CUSTOM_LIST_IMPORT_AND_SHARE_ENTRY } from './constants';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';

export type ViewMode = 'lists' | 'sections' | 'edit-list' | 'edit-section' | 'edit-table' | 'share' | 'md-text';

const FONT_AWESOME_SOLID_FAMILY: string = 'FontAwesomeSolid';
type ActionButtonKind = 'primary' | 'secondary' | 'danger';

@Component
export struct CustomListTab {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: ReferenceLang;
  @Prop isLandscape: boolean;

  @Link customLists: CustomListCollection;
  @Link scrollY: number;

  // Hoisted UI state: keep editing context stable across orientation/layout tree switches.
  @Link viewMode: ViewMode;
  @Link selectedList: CustomList | null;
  @Link selectedSection: ListSection | null;
  @Link selectedTable: MemoryTable | null;
  @Link showTableSectionPicker: boolean;

  // Edit form state
  @Link editListName: string;
  @Link editListDesc: string;
  @Link editSectionTitle: string;
  @Link editSectionContent: string;
  @Link editSectionLevel: number;
  @Link isEditing: boolean;

  // Table editor state
  @Link editHeaders: Array<string>;
  @Link editRows: Array<Array<string>>;
  @Link editRowIds: Array<string>;

  scroller: Scroller = new Scroller();
  listScroller: ListScroller = new ListScroller();
  private repository: CustomListRepository = new CustomListRepository();

  @State private mdTextName: string = '';
  @State private mdText: string = '';
  @State private mdTextLoading: boolean = false;
  @State private mdTextError: string = '';
  @State private mdTextReturnMode: ViewMode = 'lists';

  // 分享相关状态
  @State private sharePassword: string = '';
  @State private shareLink: string = '';
  @State private shareCopied: boolean = false;
  @State private shareUploading: boolean = false;
  @State private shareError: string = '';
  @State private importData: string = '';
  @State private importPassword: string = '';
  @State private importError: string = '';

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
    if (!this.editListName.trim()) {
      promptAction.showToast({ message: this.t('请输入清单名称', 'Please enter a list name') });
      return;
    }
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
    if (!this.selectedList) return;
    if (!this.editListName.trim()) {
      promptAction.showToast({ message: this.t('请输入清单名称', 'Please enter a list name') });
      return;
    }
    const ctx = this.getHostContext();
    if (!ctx) return;

    this.customLists = await this.repository.updateList(ctx, this.selectedList.id, {
      name: this.editListName.trim(),
      description: this.editListDesc.trim() || undefined,
    });

    this.selectedList = this.customLists.lists.find(l => l.id === this.selectedList?.id) || null;
    this.setViewMode(this.selectedList ? 'sections' : 'lists');
    this.onRefreshLists?.();
  }

  private async deleteList(listId: string): Promise<void> {
    const ctx = this.getHostContext();
    if (!ctx) return;

    this.customLists = await this.repository.deleteList(ctx, listId);
    if (this.selectedList?.id === listId) {
      this.selectedList = null;
      this.setViewMode('lists');
    }
    this.onRefreshLists?.();
  }

  private async createNewSection(): Promise<void> {
    if (!this.selectedList) return;
    if (!this.editSectionTitle.trim()) {
      promptAction.showToast({ message: this.t('请输入章节标题', 'Please enter a section title') });
      return;
    }
    const ctx = this.getHostContext();
    if (!ctx) return;

    // 章节仅支持 H2/H3
    const newSection = createListSection(this.editSectionTitle.trim(), this.normalizeSectionLevel(this.editSectionLevel));
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
    if (!this.selectedList || !this.selectedSection) return;
    if (!this.editSectionTitle.trim()) {
      promptAction.showToast({ message: this.t('请输入章节标题', 'Please enter a section title') });
      return;
    }
    const ctx = this.getHostContext();
    if (!ctx) return;

    const updatedList = await this.repository.updateSection(ctx, this.selectedList.id, this.selectedSection.id, {
      title: this.editSectionTitle.trim(),
      content: this.editSectionContent.trim(),
      // 章节仅支持 H2/H3
      level: this.normalizeSectionLevel(this.editSectionLevel),
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

  private normalizeSectionLevel(level: number): number {
    return level === 2 ? 2 : 3;
  }

  private actionButtonHeight(): number {
    // 增大可点击区域，避免图标按钮过小难以操作
    return this.fontSize * 2.4;
  }

  private actionButtonRadius(): number {
    return this.fontSize * 0.6;
  }

  private actionButtonGap(): number {
    return this.fontSize * 0.35;
  }

  private actionButtonPaddingX(): number {
    return this.fontSize * 0.8;
  }

  private actionButtonIconSize(): number {
    return this.fontSize * 0.95;
  }

  private actionButtonTextSize(): number {
    return this.fontSize * 0.85;
  }

  private actionButtonBgColor(kind: ActionButtonKind) {
    return kind === 'primary' ? this.theme.accentColor : this.theme.surfaceBackgroundColor;
  }

  private actionButtonFgColor(kind: ActionButtonKind) {
    if (kind === 'primary') return this.theme.chipSelectedTextColor;
    if (kind === 'danger') return '#EF4444';
    return this.theme.textColor;
  }

  private openSelectedListMarkdownTextViewer(returnMode: ViewMode = 'sections'): void {
    if (!this.selectedList) return;
    this.mdTextLoading = false;
    this.mdTextError = '';
    this.mdTextReturnMode = returnMode;
    const listName = (this.selectedList.name ?? '').trim() || this.t('未命名清单', 'Untitled list');
    this.mdTextName = `${listName}.md`;
    this.mdText = String(listToMarkdown(this.selectedList) ?? '').replace(/\r\n/g, '\n');
    if (!this.mdText.trim()) {
      this.mdTextError = this.t('清单内容为空', 'List is empty');
    }
    this.setViewMode('md-text');
  }

  private copyMarkdownText(): void {
    const text = (this.mdText ?? '').toString();
    if (!text) return;
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(pasteData);
    promptAction.showToast({ message: this.t('已复制', 'Copied') });
  }

  @Builder
  private IconTextButton(
    icon: string,
    label: string,
    kind: ActionButtonKind,
    onClick: () => void,
    enabled: boolean = true,
    layoutWeight: number = 0,
  ): void {
    Button() {
      Row({ space: this.actionButtonGap() }) {
        Text(icon)
          .fontFamily(FONT_AWESOME_SOLID_FAMILY)
          .fontSize(this.actionButtonIconSize())
          .fontColor(this.actionButtonFgColor(kind));

        Text(label)
          .fontSize(this.actionButtonTextSize())
          .fontColor(this.actionButtonFgColor(kind))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center);
    }
    .layoutWeight(layoutWeight)
    .height(this.actionButtonHeight())
    .padding({ left: this.actionButtonPaddingX(), right: this.actionButtonPaddingX() })
    .backgroundColor(this.actionButtonBgColor(kind))
    .borderRadius(this.actionButtonRadius())
    .border({ width: kind === 'primary' ? 0 : this.fontSize * 0.07, color: this.theme.borderColor })
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.5)
    .onClick(() => {
      if (!enabled) return;
      onClick();
    });
  }

  private handleBackPress(): boolean {
    if (this.viewMode === 'sections') {
      this.selectedList = null;
      this.selectedSection = null;
      this.setViewMode('lists');
      return true;
    }
    if (this.viewMode === 'md-text') {
      if (this.mdTextReturnMode === 'sections' && !this.selectedList) {
        this.setViewMode('lists');
      } else {
        this.setViewMode(this.mdTextReturnMode);
      }
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
          if (!HIDE_CUSTOM_LIST_IMPORT_AND_SHARE_ENTRY) {
            this.IconTextButton(
              '\uf56f',
              this.t('导入', 'Import'),
              'secondary',
              () => {
                this.importData = '';
                this.importPassword = '';
                this.importError = '';
                this.setViewMode('share');
              },
            );
          }

          this.IconTextButton(
            '\uf067',
            this.t('新建', 'New'),
            'primary',
            () => {
              this.editListName = '';
              this.editListDesc = '';
              this.isEditing = false;
              this.setViewMode('edit-list');
            },
          );
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

          Text(this.t('点击右上角 新建 创建清单', 'Tap New to create a list'))
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

                  Text(this.t(`${this.getTotalRows(list)} 卡片`, `${this.getTotalRows(list)} cards`))
                    .fontSize(this.fontSize * 0.8)
                    .fontColor(this.theme.mutedTextColor);
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
  private MarkdownTextView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text(this.mdTextName || this.t('Markdown 文本', 'Markdown Text'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);

      if (this.mdTextLoading) {
        Text(this.t('读取中…', 'Loading…'))
          .fontSize(this.fontSize)
          .fontColor(this.theme.mutedTextColor);
      } else if (this.mdTextError) {
        Text(this.mdTextError)
          .fontSize(this.fontSize)
          .fontColor('#EF4444')
          .maxLines(6);
      } else {
        Scroll(this.scroller) {
          Text(this.mdText)
            .width('100%')
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.textColor)
            .fontFamily('monospace')
            .lineHeight(this.fontSize * 1.25);
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }

      Column({ space: 0 }) {
        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row({ space: this.fontSize * 0.6 }) {
          this.IconTextButton(
            '\uf053',
            this.t('返回', 'Back'),
            'secondary',
            () => {
              if (this.mdTextReturnMode === 'sections' && !this.selectedList) {
                this.setViewMode('lists');
              } else {
                this.setViewMode(this.mdTextReturnMode);
              }
            },
            true,
            1,
          );

          this.IconTextButton(
            '\uf0c5',
            this.t('复制', 'Copy'),
            'primary',
            () => this.copyMarkdownText(),
            (this.mdText ?? '').trim().length > 0,
            1,
          );
        }
        .width('100%')
        .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
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
            if (!HIDE_CUSTOM_LIST_IMPORT_AND_SHARE_ENTRY) {
              this.IconTextButton(
                '\uf1e0',
                this.t('分享', 'Share'),
                'secondary',
                () => {
                  this.sharePassword = '';
                  this.shareLink = '';
                  this.shareCopied = false;
                  this.setViewMode('share');
                },
              );
            }

            this.IconTextButton(
              '\uf121',
              this.t('纯文本', 'Text'),
              'secondary',
              () => {
                this.openSelectedListMarkdownTextViewer('sections');
              },
            );

            this.IconTextButton(
              '\uf013',
            this.t('编辑', 'Edit'),
            'secondary',
            () => {
              this.editListName = this.selectedList?.name || '';
              this.editListDesc = this.selectedList?.description || '';
              this.isEditing = true;
              this.setViewMode('edit-list');
            },
          );
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Row({ space: this.fontSize * 0.5 }) {
          this.IconTextButton(
            '\uf067',
            this.t('新建章节', 'New Section'),
            'primary',
            () => {
              this.editSectionTitle = '';
              this.editSectionContent = '';
              this.editSectionLevel = 2;
              this.selectedSection = null;
              this.isEditing = false;
              this.setViewMode('edit-section');
            },
            true,
            1,
          );

          this.IconTextButton(
            '\uf0ce',
            this.t('新建表格', 'New Table'),
            'secondary',
            () => {
              if (!this.selectedList || this.selectedList.sections.length === 0) {
                promptAction.showToast({ message: this.t('请首先添加一个章节', 'Add a section first') });
                return;
              }
              this.showTableSectionPicker = true;
            },
            this.selectedList.sections.length > 0,
            1,
          );
        }
        .width('100%')
        .margin({ top: this.fontSize * 0.6 });

        if (this.showTableSectionPicker && this.selectedList) {
          Column({ space: this.fontSize * 0.4 }) {
            Text(this.t('选择一个章节给新表格', 'Pick a section to add a table'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.mutedTextColor);

            ForEach(this.selectedList.sections, (section: ListSection) => {
              Button(section.title || this.t('未命名章节', 'Untitled section'))
                .width('100%')
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.textColor)
                .backgroundColor(this.theme.surfaceBackgroundColor)
                .borderRadius(this.fontSize * 0.5)
                .padding({ top: this.fontSize * 0.65, bottom: this.fontSize * 0.65 })
                .onClick(() => this.openTableEditor(section));
            }, (section: ListSection) => section.id);

            Button(this.t('取消', 'Cancel'))
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

        if (this.selectedList.sections.length === 0) {
          Column({ space: this.fontSize }) {
            Text('\uf0ca')
              .fontFamily(FONT_AWESOME_SOLID_FAMILY)
              .fontSize(this.fontSize * 3)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('暂无章节', 'No sections yet'))
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor);

            Text(this.t('点击上方 新建章节 添加第一个章节', 'Tap New Section above to add your first section'))
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
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row({ space: this.fontSize * 0.5 }) {
        this.IconTextButton(
          '\uf044',
          this.t('编辑', 'Edit'),
          'secondary',
          () => {
            this.selectedSection = section;
            this.editSectionTitle = section.title;
            this.editSectionContent = section.content;
            this.editSectionLevel = this.normalizeSectionLevel(section.level);
            this.isEditing = true;
            this.setViewMode('edit-section');
          },
          true,
          1,
        );

        this.IconTextButton(
          '\uf0ce',
          this.t('新增表格', 'Add Table'),
          'primary',
          () => this.openTableEditor(section),
          true,
          1,
        );

        this.IconTextButton(
          '\uf2ed',
          this.t('删除', 'Delete'),
          'danger',
          () => this.showDeleteSectionConfirm(section.id),
          true,
          1,
        );
      }
      .width('100%');

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
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center);

      Row({ space: this.fontSize * 0.5 }) {
        this.IconTextButton(
          '\uf044',
          this.t('编辑表格', 'Edit Table'),
          'secondary',
          () => this.openTableEditor(section, table),
          true,
          1,
        );

        this.IconTextButton(
          '\uf2ed',
          this.t('删除表格', 'Delete Table'),
          'danger',
          () => this.showDeleteTableConfirm(table.id),
          true,
          1,
        );
      }
      .width('100%');

      if (table.headers.length > 0) {
        // Header preview
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

        // Content preview (show first 1-2 rows)
        if (table.rows.length > 0) {
          Column({ space: this.fontSize * 0.25 }) {
            ForEach(table.rows.slice(0, 2), (row: MemoryTableRow, rowIndex: number) => {
              Row() {
                ForEach(table.headers.slice(0, 3), (_: string, colIndex: number) => {
                  Text(row.cells[colIndex]?.text || '-')
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.textColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1);

                  if (colIndex < 2 && colIndex < table.headers.length - 1) {
                    Text('|')
                      .fontSize(this.fontSize * 0.75)
                      .fontColor(this.theme.borderColor)
                      .margin({ left: this.fontSize * 0.3, right: this.fontSize * 0.3 });
                  }
                }, (_: string, colIndex: number) => `row-${rowIndex}-col-${colIndex}`);

                if (table.headers.length > 3) {
                  Text('...')
                    .fontSize(this.fontSize * 0.75)
                    .fontColor(this.theme.mutedTextColor);
                }
              }
              .width('100%')
              .padding({ top: this.fontSize * 0.25, bottom: this.fontSize * 0.25 })
              .backgroundColor(this.theme.surfaceBackgroundColor)
              .borderRadius(this.fontSize * 0.25);
            }, (row: MemoryTableRow, rowIndex: number) => row.id || rowIndex.toString());
          }
          .width('100%')
          .margin({ top: this.fontSize * 0.25 });
        } else {
          Text(this.t('暂无内容', 'No rows yet'))
            .fontSize(this.fontSize * 0.75)
            .fontColor(this.theme.mutedTextColor)
            .margin({ top: this.fontSize * 0.25 });
        }
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
        Text(this.isEditing ? this.t('编辑清单', 'Edit List') : this.t('新建清单', 'New List'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .textAlign(TextAlign.Center);
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
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
        .width('100%');
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);

      Column({ space: 0 }) {
        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row({ space: this.fontSize * 0.6 }) {
          this.IconTextButton(
            '\uf00d',
            this.t('取消', 'Cancel'),
            'secondary',
            () => {
              if (!this.isEditing) {
                this.editListName = '';
                this.editListDesc = '';
              }
              this.setViewMode(this.selectedList ? 'sections' : 'lists');
            },
            true,
            1,
          );

          this.IconTextButton(
            '\uf00c',
            this.isEditing ? this.t('保存清单', 'Save List') : this.t('创建清单', 'Create List'),
            'primary',
            () => {
              if (this.isEditing) {
                this.updateSelectedList();
              } else {
                this.createNewList();
              }
            },
            true,
            1,
          );
        }
        .width('100%')
        .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  @Builder
  private EditSectionView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Row() {
        Text(this.isEditing ? this.t('编辑章节', 'Edit Section') : this.t('新建章节', 'New Section'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .textAlign(TextAlign.Center);
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);

      Scroll(this.scroller) {
        Column({ space: this.fontSize }) {
          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('标题级别', 'Heading Level'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor);

            Row({ space: this.fontSize * 0.5 }) {
              ForEach([2, 3] as Array<number>, (level: number) => {
                Text(`H${level}`)
                  .fontSize(this.fontSize * 0.85)
                  .fontColor(this.normalizeSectionLevel(this.editSectionLevel) === level ? this.theme.chipSelectedTextColor : this.theme.textColor)
                  .backgroundColor(this.normalizeSectionLevel(this.editSectionLevel) === level ? this.theme.accentColor : this.theme.surfaceBackgroundColor)
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

      Column({ space: 0 }) {
        Divider()
          .color(this.theme.borderColor)
          .strokeWidth(this.fontSize * 0.07);

        Row({ space: this.fontSize * 0.6 }) {
          this.IconTextButton(
            '\uf00d',
            this.t('取消', 'Cancel'),
            'secondary',
            () => {
              if (!this.isEditing) {
                this.editSectionTitle = '';
                this.editSectionContent = '';
                this.editSectionLevel = 2;
                this.selectedSection = null;
              }
              this.setViewMode('sections');
            },
            true,
            1,
          );

          this.IconTextButton(
            '\uf00c',
            this.isEditing ? this.t('保存章节', 'Save Section') : this.t('创建章节', 'Create Section'),
            'primary',
            () => {
              if (this.isEditing) {
                this.updateSelectedSection();
              } else {
                this.createNewSection();
              }
            },
            true,
            1,
          );
        }
        .width('100%')
        .padding({ left: this.fontSize, right: this.fontSize, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .padding(this.tabPadding());
  }

  @Builder
  private EditTableView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Stack() {
        Text(this.isEditing ? this.t('编辑表格', 'Edit Table') : this.t('新建表格', 'New Table'))
          .fontSize(this.fontSize * 1.1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textColor)
          .width('100%')
          .textAlign(TextAlign.Center);

        Row({ space: this.fontSize * 0.6 }) {
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

          Blank().layoutWeight(1);

          this.IconTextButton(
            '\uf00c',
            this.isEditing ? this.t('保存表格', 'Save Table') : this.t('创建表格', 'Create Table'),
            'primary',
            () => {
              if (this.isEditing) {
                this.updateSelectedTable();
              } else {
                this.createNewTable();
              }
            },
          );
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
      }
      .width('100%');

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
                    .placeholderColor(this.theme.mutedTextColor)
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
                    .placeholderColor(this.theme.mutedTextColor)
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
      } else if (this.viewMode === 'md-text') {
        this.MarkdownTextView();
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
    .onAppear(() => {
      setCustomListBackHandler((): boolean => this.handleBackPress());
    })
    .onDisAppear(() => clearCustomListBackHandler())
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }
}
