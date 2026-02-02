// 日历提醒功能
// 注意：HarmonyOS 日历 API 需要相应的权限配置

import reminderAgentManager from '@ohos.reminderAgentManager';

export interface ReminderConfig {
  listId: string;
  listName: string;
  hour: number;
  minute: number;
}

/**
 * 创建每日复习提醒
 * @param config 提醒配置
 * @returns 提醒ID
 */
export async function createDailyReminder(config: ReminderConfig): Promise<number> {
  const reminderRequest: reminderAgentManager.ReminderRequestAlarm = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
    hour: config.hour,
    minute: config.minute,
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7], // 每天
    title: `复习提醒: ${config.listName}`,
    content: `是时候复习「${config.listName}」清单了！`,
    expiredContent: '已过期',
    snoozeContent: '稍后提醒',
    notificationId: Math.floor(Math.random() * 10000),
    slotType: 3, // SOCIAL_COMMUNICATION
    ringDuration: 30,
    snoozeTimes: 3,
    actionButton: [
      {
        title: '开始复习',
        type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE,
      },
      {
        title: '稍后提醒',
        type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE,
      },
    ],
  };

  return await reminderAgentManager.publishReminder(reminderRequest)
    .then((id: number): number => id)
    .catch((): number => -1);
}

/**
 * 取消提醒
 * @param reminderId 提醒ID
 */
export async function cancelReminder(reminderId: number): Promise<void> {
  await reminderAgentManager.cancelReminder(reminderId)
    .then((): void => undefined)
    .catch((): void => undefined);
}

/**
 * 取消所有提醒
 */
export async function cancelAllReminders(): Promise<void> {
  await reminderAgentManager.cancelAllReminders()
    .then((): void => undefined)
    .catch((): void => undefined);
}

/**
 * 获取所有有效的提醒
 */
export async function getValidReminders(): Promise<Array<reminderAgentManager.ReminderRequest>> {
  return await reminderAgentManager.getValidReminders()
    .then((reminders: Array<reminderAgentManager.ReminderRequest>): Array<reminderAgentManager.ReminderRequest> => reminders)
    .catch((): Array<reminderAgentManager.ReminderRequest> => []);
}
