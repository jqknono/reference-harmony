// 测验数据模型

export interface QuizOption {
  text: string;
  isCorrect: boolean;
}

export interface QuizQuestion {
  id: string;
  docId: string;
  cardId: string;
  question: string;
  options: Array<QuizOption>;
  correctIndex: number;
  explanation?: string;
}

export interface QuizAnswer {
  questionId: string;
  selectedIndex: number;
  isCorrect: boolean;
  answerTime: number; // 答题耗时（毫秒）
}

export interface QuizSession {
  id: string;
  docId: string;
  docTitle: string;
  startTime: number;
  endTime: number;
  questions: Array<QuizQuestion>;
  answers: Array<QuizAnswer>;
  score: number; // 0-100
  correctCount: number;
  totalCount: number;
}

export interface QuizRecord {
  sessions: Array<QuizSession>;
  totalQuizCount: number;
  totalCorrectCount: number;
  totalQuestionCount: number;
  averageScore: number;
  lastQuizTime: number;
}

export function createEmptyQuizRecord(): QuizRecord {
  return {
    sessions: [],
    totalQuizCount: 0,
    totalCorrectCount: 0,
    totalQuestionCount: 0,
    averageScore: 0,
    lastQuizTime: 0,
  };
}

export function generateQuizSessionId(): string {
  return `quiz_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
}

export function generateQuizQuestionId(docId: string, cardId: string, index: number): string {
  return `${docId}_${cardId}_q${index}`;
}

