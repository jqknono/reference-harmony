// 测验记录存储仓库

import preferences from '@ohos.data.preferences';
import type { QuizRecord, QuizSession } from './quizModels';
import { createEmptyQuizRecord } from './quizModels';

type Preferences = preferences.Preferences;
type ValueType = preferences.ValueType;

const QUIZ_RECORD_KEY = 'quiz_record';
const MAX_SESSIONS_STORED = 50; // 最多保存50次测验记录

export class QuizRepository {
  private readonly prefsName: string = 'quiz_data';

  private async getPrefs(context: Context): Promise<Preferences | undefined> {
    return Promise.resolve()
      .then((): Promise<Preferences> => preferences.getPreferences(context, this.prefsName))
      .then(
        (p: Preferences): Preferences => p,
        (): undefined => undefined,
      );
  }

  async getQuizRecord(context: Context): Promise<QuizRecord> {
    const prefs = await this.getPrefs(context);
    if (!prefs) {
      return createEmptyQuizRecord();
    }

    const saved: string = await Promise.resolve()
      .then((): Promise<ValueType> => prefs.get(QUIZ_RECORD_KEY, ''))
      .then(
        (value: ValueType): string => (typeof value === 'string' ? value : ''),
        (): string => '',
      );

    if (!saved) {
      return createEmptyQuizRecord();
    }

    const parsed: QuizRecord | null = JSON.parse(saved) as QuizRecord | null;
    if (!parsed) {
      return createEmptyQuizRecord();
    }

    return parsed;
  }

  async saveQuizRecord(context: Context, record: QuizRecord): Promise<void> {
    const prefs = await this.getPrefs(context);
    if (!prefs) return;

    // 限制存储的会话数量
    if (record.sessions.length > MAX_SESSIONS_STORED) {
      record.sessions = record.sessions.slice(-MAX_SESSIONS_STORED);
    }

    const json = JSON.stringify(record);

    await Promise.resolve()
      .then((): Promise<void> => prefs.put(QUIZ_RECORD_KEY, json))
      .then((): void => undefined, (): void => undefined);

    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  async addQuizSession(context: Context, session: QuizSession): Promise<QuizRecord> {
    const record = await this.getQuizRecord(context);

    record.sessions.push(session);
    record.totalQuizCount += 1;
    record.totalCorrectCount += session.correctCount;
    record.totalQuestionCount += session.totalCount;
    record.lastQuizTime = session.endTime;

    if (record.totalQuestionCount > 0) {
      record.averageScore = Math.round(
        (record.totalCorrectCount / record.totalQuestionCount) * 100
      );
    }

    await this.saveQuizRecord(context, record);
    return record;
  }

  async clearAllRecords(context: Context): Promise<void> {
    const prefs = await this.getPrefs(context);
    if (!prefs) return;

    await Promise.resolve()
      .then((): Promise<void> => prefs.delete(QUIZ_RECORD_KEY))
      .then((): void => undefined, (): void => undefined);

    await Promise.resolve()
      .then((): Promise<void> => prefs.flush())
      .then((): void => undefined, (): void => undefined);
  }

  getRecentSessions(record: QuizRecord, count: number): Array<QuizSession> {
    if (record.sessions.length <= count) {
      return record.sessions.slice().reverse();
    }
    return record.sessions.slice(-count).reverse();
  }

  getDocQuizHistory(record: QuizRecord, docId: string): Array<QuizSession> {
    const sessions: Array<QuizSession> = [];
    for (let i = record.sessions.length - 1; i >= 0; i--) {
      if (record.sessions[i].docId === docId) {
        sessions.push(record.sessions[i]);
      }
    }
    return sessions;
  }
}

