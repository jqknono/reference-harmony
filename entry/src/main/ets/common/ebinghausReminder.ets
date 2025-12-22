import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import wantAgent from '@ohos.app.ability.wantAgent';
import type common from '@ohos.app.ability.common';
import type { Context } from '@ohos.abilityAccessCtrl';
import type { Want } from '@kit.AbilityKit';
import type { ReferenceDocSummary } from './referenceModels';

/**
 * WantAgent 在不同 kit / SDK 版本里的导出方式不一致。
 * 这里用最小兼容结构类型，避免依赖某个特定的类型名/导出路径。
 */
interface WantAgentCompat {
  pkgName: string;
  abilityName: string;
}

class RecentDocsNotificationWantParams {
  launchAction: string;
  recentDocId: string;

  constructor(launchAction: string, recentDocId: string) {
    this.launchAction = launchAction;
    this.recentDocId = recentDocId;
  }
}

/**
 * 艾宾浩斯记忆曲线的复习时间间隔（分钟）
 * 学习后 20分钟、1小时、9小时、1天、2天、6天、15天、31天
 */
const EBBINGHAUS_INTERVALS_MINUTES: number[] = [
  20,           // 20分钟
  60,           // 1小时
  9 * 60,       // 9小时
  24 * 60,      // 1天
  2 * 24 * 60,  // 2天
  6 * 24 * 60,  // 6天
  15 * 24 * 60, // 15天
  31 * 24 * 60, // 31天
];

/**
 * 调试模式的时间间隔（秒）- 每20秒一个通知
 */
const DEBUG_INTERVALS_SECONDS: number[] = [
  20,   // 20秒
  40,   // 40秒
  60,   // 60秒
  80,   // 80秒
  100,  // 100秒
  120,  // 120秒
  140,  // 140秒
  160,  // 160秒
];

/**
 * 调试模式阶段的中文描述
 */
const DEBUG_STAGE_LABELS_ZH: string[] = [
  '20秒测试',
  '40秒测试',
  '60秒测试',
  '80秒测试',
  '100秒测试',
  '120秒测试',
  '140秒测试',
  '160秒测试',
];

/**
 * 调试模式阶段的英文描述
 */
const DEBUG_STAGE_LABELS_EN: string[] = [
  '20s test',
  '40s test',
  '60s test',
  '80s test',
  '100s test',
  '120s test',
  '140s test',
  '160s test',
];

/**
 * 复习阶段的中文描述
 */
const STAGE_LABELS_ZH: string[] = [
  '20分钟复习',
  '1小时复习',
  '9小时复习',
  '1天复习',
  '2天复习',
  '6天复习',
  '15天复习',
  '31天复习',
];

/**
 * 复习阶段的英文描述
 */
const STAGE_LABELS_EN: string[] = [
  '20min review',
  '1hr review',
  '9hr review',
  '1day review',
  '2day review',
  '6day review',
  '15day review',
  '31day review',
];

// 存储已调度的提醒 ID（系统级 ReminderAgent 或本地通知 ID）
let publishedReminderIds: number[] = [];
// 存储 setTimeout 的句柄，用于取消尚未触发的本地通知（仅降级模式使用）
let scheduledReminderTimers: number[] = [];
// 标记当前是否使用系统级 ReminderAgent（true）还是本地定时器降级（false）
let usingSystemReminder: boolean = false;

/**
 * 艾宾浩斯记忆提醒管理器
 */
export class EbbinghausReminderManager {
  private static readonly REMINDER_ID_BASE: number = 100000;
  private static readonly BUNDLE_NAME: string = 'reference.app.jqknono.com';
  private static readonly RECENT_DOCS_NOTIFICATION_ID: number = 200001;
  private static readonly RECENT_DOCS_NOTIFICATION_LAUNCH_ACTION_KEY: string = 'launchAction';
  private static readonly RECENT_DOCS_NOTIFICATION_LAUNCH_DOC_ID_KEY: string = 'recentDocId';
  private static readonly RECENT_DOCS_NOTIFICATION_LAUNCH_ACTION_VALUE: string = 'openRecentDocs';

  private static lastReminderPublishErrorCode: number = 0;
  private static lastReminderPublishErrorMessage: string = '';

  static getLastReminderPublishErrorText(): string {
    const code: number = EbbinghausReminderManager.lastReminderPublishErrorCode;
    const msg: string = EbbinghausReminderManager.lastReminderPublishErrorMessage;
    if (!code && !msg) return '';
    if (code && msg) return `${code}: ${msg}`;
    if (code) return String(code);
    return msg;
  }

  /**
   * 返回当前是否使用系统级 ReminderAgent（true 表示杀掉进程后仍会通知）
   */
  static isUsingSystemReminder(): boolean {
    return usingSystemReminder;
  }

  private static async buildReviewReminderWantAgent(): Promise<WantAgentCompat | undefined> {
    const w: Want = {
      bundleName: EbbinghausReminderManager.BUNDLE_NAME,
      abilityName: 'EntryAbility',
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [w],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
    };
    return Promise.resolve()
      .then((): Promise<WantAgentCompat> => wantAgent.getWantAgent(info) as Promise<WantAgentCompat>)
      .then((agent: WantAgentCompat): WantAgentCompat => agent, (): undefined => undefined);
  }

  private static async ensureNotificationSlot(): Promise<void> {
    await Promise.resolve()
      .then((): Promise<void> => notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION))
      .then((): void => undefined, (): void => undefined);
  }

  private static async buildRecentDocsNotificationWantAgent(recentDocs: Array<ReferenceDocSummary>): Promise<WantAgentCompat | undefined> {
    const docId: string = recentDocs.length > 0 ? (recentDocs[0]?.id ?? '') : '';
    const params: RecentDocsNotificationWantParams = new RecentDocsNotificationWantParams(
      EbbinghausReminderManager.RECENT_DOCS_NOTIFICATION_LAUNCH_ACTION_VALUE,
      docId,
    );
    const w: Want = {
      bundleName: EbbinghausReminderManager.BUNDLE_NAME,
      abilityName: 'EntryAbility',
      parameters: (params as Object) as Record<string, Object>,
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [w],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
    };
    return Promise.resolve()
      .then((): Promise<WantAgentCompat> => wantAgent.getWantAgent(info) as Promise<WantAgentCompat>)
      .then((agent: WantAgentCompat): WantAgentCompat => agent, (): undefined => undefined);
  }

  static async syncActiveReminders(context: Context): Promise<number> {
    if (usingSystemReminder) {
      // 尝试从系统查询有效的提醒数量
      const queried: number[] | undefined = await EbbinghausReminderManager.queryValidReminderIds();
      if (queried !== undefined) {
        publishedReminderIds = queried;
      }
    }
    return publishedReminderIds.length;
  }

  private static async queryValidReminderIds(): Promise<number[] | undefined> {
    return Promise.resolve()
      .then(
        (): Promise<Array<reminderAgentManager.ReminderInfo>> => reminderAgentManager.getAllValidReminders(),
      )
      .then(
        (infos: Array<reminderAgentManager.ReminderInfo>): number[] => {
          const ids: number[] = [];
          for (let i = 0; i < infos.length; i++) {
            const id: number = infos[i].reminderId;
            if (Number.isFinite(id) && id > 0) ids.push(id);
          }
          return ids;
        },
        (): undefined => undefined,
      );
  }

  static async hydrate(context: Context): Promise<void> {
    // 尝试同步系统级提醒
    await EbbinghausReminderManager.syncActiveReminders(context);
  }

  /**
   * 发布艾宾浩斯记忆提醒
   * 优先尝试系统级 ReminderAgent（支持进程被杀后仍触发），失败则降级到本地定时器。
   */
  static async publishReminders(context: Context, lang: string, debugMode: boolean = false): Promise<number[]> {
    EbbinghausReminderManager.lastReminderPublishErrorCode = 0;
    EbbinghausReminderManager.lastReminderPublishErrorMessage = '';

    // 如果还有已知的提醒未被取消，不重复发布
    if (publishedReminderIds.length > 0) {
      return publishedReminderIds.slice();
    }

    const isZh: boolean = lang !== 'en';
    const intervals: number[] = debugMode ? DEBUG_INTERVALS_SECONDS : EBBINGHAUS_INTERVALS_MINUTES;
    const stageLabels: string[] = debugMode
      ? (isZh ? DEBUG_STAGE_LABELS_ZH : DEBUG_STAGE_LABELS_EN)
      : (isZh ? STAGE_LABELS_ZH : STAGE_LABELS_EN);

    // 先尝试系统级 ReminderAgent
    const systemResult: number[] = await EbbinghausReminderManager.tryPublishSystemReminders(
      isZh, debugMode, intervals, stageLabels,
    );
    if (systemResult.length > 0) {
      usingSystemReminder = true;
      publishedReminderIds = systemResult;
      return systemResult;
    }

    // 系统级失败，降级到本地定时器
    usingSystemReminder = false;
    const localResult: number[] = await EbbinghausReminderManager.publishLocalReminders(
      isZh, debugMode, intervals, stageLabels,
    );
    publishedReminderIds = localResult;
    return localResult;
  }

  /**
   * 尝试使用系统级 ReminderAgent 发布提醒
   */
  private static async tryPublishSystemReminders(
    isZh: boolean,
    debugMode: boolean,
    intervals: number[],
    stageLabels: string[],
  ): Promise<number[]> {
    const reminderWantAgent: WantAgentCompat | undefined = await EbbinghausReminderManager.buildReviewReminderWantAgent();

    const newIds: number[] = [];
    let stopOnLimit: boolean = false;
    let systemApiBlocked: boolean = false;

    for (let i = 0; i < intervals.length; i++) {
      if (stopOnLimit || systemApiBlocked) break;
      const interval: number = intervals[i];
      const stageLabel: string = stageLabels[i];
      const triggerSeconds: number = debugMode ? interval : interval * 60;

      const timerRequest: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: triggerSeconds,
        title: isZh
          ? (debugMode ? '开发速查 - 调试提醒' : '开发速查 - 复习提醒')
          : (debugMode ? 'Quick Reference - Debug Reminder' : 'Quick Reference - Review Reminder'),
        content: isZh
          ? (debugMode
            ? `${stageLabel}：调试模式通知测试`
            : `${stageLabel}：是时候复习了，根据艾宾浩斯记忆曲线，现在复习效果最佳！`)
          : (debugMode
            ? `${stageLabel}: Debug mode notification test`
            : `${stageLabel}: Time to review! According to the Ebbinghaus curve, now is the best time to review!`),
        wantAgent: reminderWantAgent,
      };

      const reminderId: number | undefined = await Promise.resolve()
        .then((): Promise<number> => reminderAgentManager.publishReminder(timerRequest))
        .then(
          (id: number): number => id,
          (err: BusinessError): undefined => {
            console.warn(`[EbbinghausReminder] System reminder failed ${i}: ${err.code} ${err.message}`);
            EbbinghausReminderManager.lastReminderPublishErrorCode = err.code;
            const rawMsg: string = err.message ?? '';
            // 检测 system-api 限制
            if (rawMsg.includes('not system-app') || rawMsg.includes('system-api')) {
              systemApiBlocked = true;
              EbbinghausReminderManager.lastReminderPublishErrorMessage =
                '系统级提醒(ReminderAgent)在当前环境属于 system-api，已降级为本地定时器（应用被杀后无法通知）';
            } else {
              EbbinghausReminderManager.lastReminderPublishErrorMessage = rawMsg;
            }
            if (err.code === 1700002) {
              stopOnLimit = true;
            }
            return undefined;
          },
        );

      if (reminderId !== undefined) {
        newIds.push(reminderId);
      }
    }

    // 如果被 system-api 阻止，取消已发布的并返回空数组以触发降级
    if (systemApiBlocked && newIds.length > 0) {
      for (let i = 0; i < newIds.length; i++) {
        await Promise.resolve()
          .then((): Promise<void> => reminderAgentManager.cancelReminder(newIds[i]))
          .then((): void => undefined, (): void => undefined);
      }
      return [];
    }

    return newIds;
  }

  /**
   * 使用本地定时器 + NotificationKit 发布提醒（降级方案）
   */
  private static async publishLocalReminders(
    isZh: boolean,
    debugMode: boolean,
    intervals: number[],
    stageLabels: string[],
  ): Promise<number[]> {
    await EbbinghausReminderManager.ensureNotificationSlot();

    const reminderWantAgent: WantAgentCompat | undefined = await EbbinghausReminderManager.buildReviewReminderWantAgent();
    const newIds: number[] = [];

    for (let i = 0; i < intervals.length; i++) {
      const interval: number = intervals[i];
      const stageLabel: string = stageLabels[i];
      const triggerSeconds: number = debugMode ? interval : interval * 60;

      const notifyId: number = EbbinghausReminderManager.REMINDER_ID_BASE + i;
      const title: string = isZh
        ? (debugMode ? '开发速查 - 调试提醒' : '开发速查 - 复习提醒')
        : (debugMode ? 'Quick Reference - Debug Reminder' : 'Quick Reference - Review Reminder');
      const text: string = isZh
        ? (debugMode
          ? `${stageLabel}：调试模式通知测试`
          : `${stageLabel}：是时候复习了，根据艾宾浩斯记忆曲线，现在复习效果最佳！`)
        : (debugMode
          ? `${stageLabel}: Debug mode notification test`
          : `${stageLabel}: Time to review! According to the Ebbinghaus curve, now is the best time to review!`);

      const request: notificationManager.NotificationRequest = {
        id: notifyId,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
          },
        },
      };
      if (reminderWantAgent) {
        request.wantAgent = reminderWantAgent;
      }

      newIds.push(notifyId);
      const timerId: number = setTimeout(() => {
        Promise.resolve()
          .then((): Promise<void> => notificationManager.publish(request))
          .then((): void => undefined, (): void => undefined);
      }, triggerSeconds * 1000);
      scheduledReminderTimers.push(timerId);
    }

    return newIds;
  }

  /**
   * 取消所有艾宾浩斯记忆提醒
   */
  static async cancelAllReminders(context: Context): Promise<void> {
    if (usingSystemReminder) {
      // 取消系统级提醒
      const ids: number[] = publishedReminderIds.slice();
      for (let i = 0; i < ids.length; i++) {
        await Promise.resolve()
          .then((): Promise<void> => reminderAgentManager.cancelReminder(ids[i]))
          .then((): void => undefined, (): void => undefined);
      }
    } else {
      // 取消本地定时器
      for (let i = 0; i < scheduledReminderTimers.length; i++) {
        clearTimeout(scheduledReminderTimers[i]);
      }
      scheduledReminderTimers = [];

      // 取消已发布的本地通知
      const ids: number[] = publishedReminderIds.slice();
      for (let i = 0; i < ids.length; i++) {
        await Promise.resolve()
          .then((): Promise<void> => notificationManager.cancel(ids[i]))
          .then((): void => undefined, (): void => undefined);
      }
    }
    publishedReminderIds = [];
  }

  /**
   * 获取当前有效的艾宾浩斯提醒数量
   */
  static getActiveReminderCount(): number {
    return publishedReminderIds.length;
  }

  /**
   * 获取艾宾浩斯记忆曲线的阶段描述
   */
  static getStageLabels(lang: string): string[] {
    return lang === 'en' ? STAGE_LABELS_EN.slice() : STAGE_LABELS_ZH.slice();
  }

  /**
   * 获取艾宾浩斯记忆曲线的时间间隔描述
   */
  static getIntervalDescription(lang: string, debugMode: boolean = false): string {
    const isZh: boolean = lang !== 'en';
    if (debugMode) {
      return isZh
        ? '调试模式：每20秒发送一次通知'
        : 'Debug mode: notification every 20 seconds';
    }
    return isZh
      ? '复习时间点：20分钟、1小时、9小时、1天、2天、6天、15天、31天'
      : 'Review times: 20min, 1hr, 9hr, 1day, 2day, 6day, 15day, 31day';
  }

  /**
   * 检查通知权限是否已开启
   * @returns true 表示通知权限已开启，false 表示未开启
   */
  static async isNotificationEnabled(): Promise<boolean> {
    return Promise.resolve()
      .then((): Promise<boolean> => notificationManager.isNotificationEnabled())
      .then(
        (enabled: boolean): boolean => enabled,
        (): boolean => false,
      );
  }

  private static buildNotificationSettingsWant(): Want {
    return {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'systemui_notification_settings',
    };
  }

  /**
   * 请求用户开启通知权限
   * 跳转到系统通知设置页面
   */
  static async requestEnableNotification(host: common.UIAbilityContext): Promise<void> {
    await Promise.resolve()
      .then((): Promise<void> => host.startAbility(EbbinghausReminderManager.buildNotificationSettingsWant()))
      .then((): void => undefined, (): void => undefined);
  }

  /**
   * 发布/更新「最近打开」系统通知（用于在通知栏展示最近打开的3个清单简介）
   */
  static async publishRecentDocsNotification(
    lang: string,
    recentDocs: Array<ReferenceDocSummary>,
  ): Promise<void> {
    const isZh: boolean = lang !== 'en';
    const title: string = isZh ? '开发速查 - 最近打开' : 'Quick Reference - Recently Opened';
    const emptyText: string = isZh ? '暂无最近打开的清单' : 'No recent lists';

    const lines: string[] = [];
    for (let i = 0; i < recentDocs.length; i++) {
      const item = recentDocs[i];
      const name: string = (item?.name ?? '').trim();
      const intro: string = (item?.title ?? '').trim();
      const label = `${i + 1}. ${name || (isZh ? '未命名' : 'Untitled')}`;
      lines.push(intro ? (isZh ? `${label}：${intro}` : `${label}: ${intro}`) : label);
    }
    const text: string = lines.length > 0 ? lines.join('\n') : emptyText;

    await EbbinghausReminderManager.ensureNotificationSlot();

    const agent: WantAgentCompat | undefined = await EbbinghausReminderManager.buildRecentDocsNotificationWantAgent(recentDocs);

    const request: notificationManager.NotificationRequest = {
      id: EbbinghausReminderManager.RECENT_DOCS_NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
        },
      },
    };
    if (agent) {
      request.wantAgent = agent;
    }

    await Promise.resolve()
      .then((): Promise<void> => notificationManager.publish(request))
      .then((): void => undefined, (): void => undefined);
  }

  /**
   * 取消「最近打开」系统通知
   */
  static async cancelRecentDocsNotification(): Promise<void> {
    await Promise.resolve()
      .then((): Promise<void> => notificationManager.cancel(EbbinghausReminderManager.RECENT_DOCS_NOTIFICATION_ID))
      .then((): void => undefined, (): void => undefined);
  }
}
