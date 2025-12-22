// 测验工具 - 从表格内容生成选择题

import type { ReferenceCardData, ReferenceDoc } from './referenceModels';
import type { QuizQuestion, QuizOption } from './quizModels';
import { generateQuizQuestionId } from './quizModels';
import { decodeIfEncoded } from './encodedContent';

interface TableRow {
  cells: Array<string>;
}

interface ParsedTable {
  headers: Array<string>;
  rows: Array<TableRow>;
}

function normalizeNewlines(input: string): string {
  return input.split('\r\n').join('\n').split('\r').join('\n');
}

function splitTableRow(trimmedLine: string): Array<string> {
  // Markdown 表格行解析：
  // - `\|` 表示单元格内的字面量 `|`，不应当作为分隔符
  // - 行内代码（反引号包裹）中的 `|` 也不应当作为分隔符
  const line = trimmedLine.trim();
  const cells: Array<string> = [];

  let current = '';
  let inInlineCode = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line.charAt(i);

    // 处理转义：\| -> |
    if (ch === '\\' && i + 1 < line.length) {
      const next = line.charAt(i + 1);
      if (next === '|') {
        current += '|';
        i += 1;
        continue;
      }
      current += ch;
      continue;
    }

    // 行内代码切换（简单支持：单个反引号）
    if (ch === '`') {
      inInlineCode = !inInlineCode;
      current += ch;
      continue;
    }

    // 列分隔符：不在行内代码内时生效
    if (ch === '|' && !inInlineCode) {
      cells.push(current.trim());
      current = '';
      continue;
    }

    current += ch;
  }

  cells.push(current.trim());

  // 去除表格两侧可能存在的空单元格（如以 `|` 开头/结尾）
  while (cells.length > 0 && !cells[0]) {
    cells.shift();
  }
  while (cells.length > 0 && !cells[cells.length - 1]) {
    cells.pop();
  }

  return cells;
}

function looksLikeTableSeparatorLine(trimmedLine: string): boolean {
  if (trimmedLine.indexOf('|') < 0) return false;
  const cells = splitTableRow(trimmedLine);
  if (cells.length < 2) return false;
  for (let i = 0; i < cells.length; i++) {
    const raw = cells[i];
    const s = raw.split(' ').join('');
    if (!s) return false;
    let hasDash = false;
    for (let j = 0; j < s.length; j++) {
      const ch = s.charAt(j);
      if (ch === '-') hasDash = true;
      if (ch !== '-' && ch !== ':') return false;
    }
    if (!hasDash) return false;
  }
  return true;
}

function stripMarkdownFormatting(text: string): string {
  // 移除代码块标记
  let result = text.replace(/`([^`]+)`/g, '$1');
  // 移除粗体
  result = result.replace(/\*\*([^*]+)\*\*/g, '$1');
  result = result.replace(/__([^_]+)__/g, '$1');
  // 移除斜体
  result = result.replace(/\*([^*]+)\*/g, '$1');
  result = result.replace(/_([^_]+)_/g, '$1');
  // 移除链接，保留文本
  result = result.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');
  return result.trim();
}

function parseTableFromMarkdown(body: string): ParsedTable | null {
  const text = normalizeNewlines(body);
  const lines = text.split('\n');

  let headerLine: string | null = null;
  let separatorLineIndex = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    if (line.indexOf('|') < 0) continue;

    if (i + 1 < lines.length) {
      const nextLine = lines[i + 1].trim();
      if (looksLikeTableSeparatorLine(nextLine)) {
        headerLine = line;
        separatorLineIndex = i + 1;
        break;
      }
    }
  }

  if (!headerLine || separatorLineIndex < 0) return null;

  const headers = splitTableRow(headerLine);
  if (headers.length < 2) return null;

  const rows: Array<TableRow> = [];
  for (let i = separatorLineIndex + 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) break;
    if (line.indexOf('|') < 0) break;
    if (looksLikeTableSeparatorLine(line)) continue;

    const cells = splitTableRow(line);
    if (cells.length > 0) {
      rows.push({ cells });
    }
  }

  if (rows.length < 2) return null; // 需要至少2行数据才能生成题目

  return { headers, rows };
}

function shuffleArray<T>(array: Array<T>): Array<T> {
  const result = array.slice();
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const temp = result[i];
    result[i] = result[j];
    result[j] = temp;
  }
  return result;
}

function generateQuestionsFromTable(
  docId: string,
  cardId: string,
  cardTitle: string,
  table: ParsedTable,
): Array<QuizQuestion> {
  const questions: Array<QuizQuestion> = [];

  // 至少需要2列才能生成题目
  if (table.headers.length < 2 || table.rows.length < 2) {
    return questions;
  }

  // 策略1: 问第一列，选第二列的答案
  // 策略2: 问第二列，选第一列的答案

  const col0Values: Array<string> = [];
  const col1Values: Array<string> = [];

  for (let i = 0; i < table.rows.length; i++) {
    const row = table.rows[i];
    if (row.cells.length >= 2) {
      const v0 = stripMarkdownFormatting(row.cells[0]);
      const v1 = stripMarkdownFormatting(row.cells[1]);
      if (v0 && v1) {
        col0Values.push(v0);
        col1Values.push(v1);
      }
    }
  }

  if (col0Values.length < 2) return questions;

  const header0 = stripMarkdownFormatting(table.headers[0]) || '项目';
  const header1 = stripMarkdownFormatting(table.headers[1]) || '描述';

  // 生成题目：给出第一列的值，问第二列是什么
  for (let i = 0; i < col0Values.length && questions.length < 10; i++) {
    const correctValue = col1Values[i];
    const questionText = `【${cardTitle}】"${col0Values[i]}" 的 ${header1} 是什么？`;

    // 收集干扰项（从其他行的第二列值中选取，去重）
    const distractors: Array<string> = [];
    for (let j = 0; j < col1Values.length; j++) {
      if (j !== i && col1Values[j] !== correctValue) {
        // 检查是否已存在相同的干扰项
        let exists = false;
        for (let k = 0; k < distractors.length; k++) {
          if (distractors[k] === col1Values[j]) {
            exists = true;
            break;
          }
        }
        if (!exists) {
          distractors.push(col1Values[j]);
        }
      }
    }

    if (distractors.length < 2) continue; // 需要至少2个干扰项

    // 随机选择2-3个干扰项
    const shuffledDistractors = shuffleArray(distractors);
    const selectedDistractors = shuffledDistractors.slice(0, Math.min(3, shuffledDistractors.length));

    // 构建选项
    const options: Array<QuizOption> = [
      { text: correctValue, isCorrect: true },
    ];
    for (let d = 0; d < selectedDistractors.length; d++) {
      options.push({ text: selectedDistractors[d], isCorrect: false });
    }

    // 打乱选项顺序
    const shuffledOptions = shuffleArray(options);
    let correctIndex = 0;
    for (let k = 0; k < shuffledOptions.length; k++) {
      if (shuffledOptions[k].isCorrect) {
        correctIndex = k;
        break;
      }
    }

    questions.push({
      id: generateQuizQuestionId(docId, cardId, i),
      docId,
      cardId,
      question: questionText,
      options: shuffledOptions,
      correctIndex,
      explanation: `正确答案：${correctValue}`,
    });
  }

  return questions;
}

export function extractQuestionsFromCard(
  docId: string,
  card: ReferenceCardData,
): Array<QuizQuestion> {
  const encoded = card.encoded === true;
  const body = decodeIfEncoded(card.body ?? '', encoded);

  if (!body) return [];

  const table = parseTableFromMarkdown(body);
  if (!table) return [];

  const cardTitle = decodeIfEncoded(card.title ?? '', encoded) || card.id;

  return generateQuestionsFromTable(docId, card.id, cardTitle, table);
}

export function extractQuestionsFromDoc(doc: ReferenceDoc): Array<QuizQuestion> {
  const allQuestions: Array<QuizQuestion> = [];

  for (let i = 0; i < doc.cards.length; i++) {
    const card = doc.cards[i];
    if (card.sectionId === 'intro') continue;

    const questions = extractQuestionsFromCard(doc.id, card);
    for (let j = 0; j < questions.length; j++) {
      allQuestions.push(questions[j]);
    }
  }

  return allQuestions;
}

export function selectRandomQuestions(
  questions: Array<QuizQuestion>,
  count: number,
): Array<QuizQuestion> {
  if (questions.length <= count) {
    return shuffleArray(questions);
  }
  const shuffled = shuffleArray(questions);
  return shuffled.slice(0, count);
}

export function calculateScore(correctCount: number, totalCount: number): number {
  if (totalCount <= 0) return 0;
  return Math.round((correctCount / totalCount) * 100);
}

