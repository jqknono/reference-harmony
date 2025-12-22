import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import type { Context } from '@ohos.abilityAccessCtrl';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

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

// 存储已发布的提醒 ID
let publishedReminderIds: number[] = [];
let hasHydratedFromPrefs: boolean = false;

const PREFS_NAME: string = 'settings';
const PREF_KEY_REMINDER_IDS: string = 'ebbinghausReminderIds';

/**
 * 艾宾浩斯记忆提醒管理器
 */
export class EbbinghausReminderManager {
  private static readonly REMINDER_ID_BASE: number = 100000;
  private static readonly BUNDLE_NAME: string = 'reference.app.jqknono.com';

  private static decodeIds(value: ValueType): number[] {
    if (typeof value !== 'string') return [];
    const text: string = value.trim();
    if (text.length === 0) return [];

    const parts: string[] = text.split(',');
    const ids: number[] = [];
    for (let i = 0; i < parts.length; i++) {
      const n: number = Number(parts[i]);
      if (Number.isFinite(n) && n > 0) {
        ids.push(n);
      }
    }
    return ids;
  }

  private static encodeIds(ids: number[]): string {
    if (ids.length === 0) return '';
    return ids.join(',');
  }

  private static async getPrefs(context: Context): Promise<Preferences | undefined> {
    return Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, PREFS_NAME))
      .then((p: Preferences): Preferences => p, (): undefined => undefined);
  }

  private static async ensureHydrated(context: Context): Promise<void> {
    if (hasHydratedFromPrefs) return;

    const prefs: Preferences | undefined = await EbbinghausReminderManager.getPrefs(context);
    if (!prefs) {
      hasHydratedFromPrefs = true;
      return;
    }

    const raw: ValueType = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(PREF_KEY_REMINDER_IDS, ''))
      .then((v: ValueType): ValueType => v, (): ValueType => '');

    publishedReminderIds = EbbinghausReminderManager.decodeIds(raw);
    hasHydratedFromPrefs = true;
  }

  private static async persistIds(context: Context): Promise<void> {
    const prefs: Preferences | undefined = await EbbinghausReminderManager.getPrefs(context);
    if (!prefs) return;

    const encoded: string = EbbinghausReminderManager.encodeIds(publishedReminderIds);
    await Promise.resolve()
      .then((): Promise<void> => prefs.put(PREF_KEY_REMINDER_IDS, encoded))
      .then((): void => undefined, (): void => undefined);
    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  static async hydrate(context: Context): Promise<void> {
    await EbbinghausReminderManager.ensureHydrated(context);
  }

  /**
   * 发布艾宾浩斯记忆提醒
   * 会将发布的提醒 ID 持久化，避免应用重启后无法取消导致提醒数量超限。
   * @param host HostContext
   * @param lang 语言设置
   * @returns 发布的提醒 ID 数组
   */
  static async publishReminders(context: Context, lang: string): Promise<number[]> {
    await EbbinghausReminderManager.ensureHydrated(context);
    const newIds: number[] = [];
    const isZh: boolean = lang !== 'en';
    let stopOnLimit: boolean = false;

    for (let i = 0; i < EBBINGHAUS_INTERVALS_MINUTES.length; i++) {
      if (stopOnLimit) break;
      const intervalMinutes: number = EBBINGHAUS_INTERVALS_MINUTES[i];
      const stageLabel: string = isZh ? STAGE_LABELS_ZH[i] : STAGE_LABELS_EN[i];

      const timerRequest: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: intervalMinutes * 60,
        title: isZh ? '开发速查 - 复习提醒' : 'Quick Reference - Review Reminder',
        content: isZh
          ? `${stageLabel}：是时候复习了，根据艾宾浩斯记忆曲线，现在复习效果最佳！`
          : `${stageLabel}: Time to review! According to the Ebbinghaus curve, now is the best time to review!`,
        expiredContent: isZh ? '提醒已过期' : 'Reminder expired',
        snoozeContent: isZh ? '稍后提醒' : 'Snooze',
        notificationId: EbbinghausReminderManager.REMINDER_ID_BASE + i,
        slotType: 2, // SOCIAL_COMMUNICATION
        wantAgent: {
          pkgName: EbbinghausReminderManager.BUNDLE_NAME,
          abilityName: 'EntryAbility',
        },
        actionButton: [
          {
            title: isZh ? '关闭' : 'Dismiss',
            type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE,
          },
        ],
      };

      const reminderId: number | undefined = await Promise.resolve()
        .then((): Promise<number> => reminderAgentManager.publishReminder(timerRequest))
        .then(
          (id: number): number => id,
          (err: BusinessError): undefined => {
            console.error(`[EbbinghausReminder] Failed to publish reminder ${i}: ${err.code} ${err.message}`);
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

    publishedReminderIds = newIds;
    await EbbinghausReminderManager.persistIds(context);
    return newIds;
  }

  /**
   * 取消所有艾宾浩斯记忆提醒
   */
  static async cancelAllReminders(context: Context): Promise<void> {
    await EbbinghausReminderManager.ensureHydrated(context);

    // 逐个取消已记录的提醒（ArkTS 不支持对 namespace 做反射式调用，也不支持 Function.call/apply）
    for (let i = 0; i < publishedReminderIds.length; i++) {
      const reminderId: number = publishedReminderIds[i];
      await Promise.resolve()
        .then((): Promise<void> => reminderAgentManager.cancelReminder(reminderId))
        .then(
          (): void => undefined,
          (err: BusinessError): void => {
            console.error(`[EbbinghausReminder] Failed to cancel reminder ${reminderId}: ${err.code} ${err.message}`);
          },
        );
    }

    publishedReminderIds = [];
    await EbbinghausReminderManager.persistIds(context);
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
  static getIntervalDescription(lang: string): string {
    const isZh: boolean = lang !== 'en';
    return isZh
      ? '复习时间点：20分钟、1小时、9小时、1天、2天、6天、15天、31天'
      : 'Review times: 20min, 1hr, 9hr, 1day, 2day, 6day, 15day, 31day';
  }
}
