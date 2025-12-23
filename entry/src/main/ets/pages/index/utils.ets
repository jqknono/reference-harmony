import type { CardMargin } from './types';
import type { ReferenceCardData } from '../../common/referenceModels';
import { decodeIfEncoded } from '../../common/encodedContent';

export function makeCardMargin(fontSize: number): CardMargin {
  const margin: CardMargin = {
    left: fontSize * 1,
    right: fontSize * 1,
    top: fontSize * 0.5,
    bottom: fontSize * 0.5
  };
  return margin;
}

export function lengthToNumber(value: Length): number {
  if (typeof value === 'number') return value;
  const parsed: number = Number.parseFloat(String(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

export function toHexColorString(color: number): string {
  const value: number = color >>> 0;
  const hex: string = value.toString(16);
  const normalized: string = (hex.length <= 6 ? hex.padStart(6, '0') : hex.padStart(8, '0'));
  return `#${normalized}`;
}

export function getAvatarText(label: string): string {
  const trimmed: string = (label ?? '').trim();
  if (!trimmed) return '?';
  const chars: Array<string> = Array.from(trimmed);
  let picked: string = chars[0] ?? '?';
  if (picked === '.' && chars.length > 1) {
    picked = chars[1];
  }
  return picked.toUpperCase();
}

export function iconKey(docId: string, icon: string | undefined): string {
  if (!icon) return docId;
  const trimmed = icon.trim();
  if (!trimmed) return docId;
  if (trimmed.startsWith('data:')) return docId;
  return `${docId}:${trimmed}`;
}

export function isRemoteIcon(icon: string | undefined): boolean {
  const s: string = (icon ?? '').trim().toLowerCase();
  return s.startsWith('http://') || s.startsWith('https://');
}

export function trimmedIcon(icon: string | undefined): string {
  return (icon ?? '').trim();
}

export function isRawfileIcon(icon: string | undefined): boolean {
  const s = trimmedIcon(icon);
  return s.startsWith('reference/');
}

export function isSvgIcon(icon: string | undefined): boolean {
  const s: string = trimmedIcon(icon).toLowerCase();
  return s.endsWith('.svg');
}

export function normalizeSearchTokens(query: string): Array<string> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  return trimmed
    .split(/\s+/)
    .map((part: string): string => part.trim().toLowerCase())
    .filter((part: string): boolean => !!part);
}

export function cardMatchesTokens(card: ReferenceCardData, tokens: Array<string>): boolean {
  if (tokens.length === 0) return true;
  const encoded: boolean = card.encoded === true;
  const haystack = [
    decodeIfEncoded(card.title ?? '', encoded),
    decodeIfEncoded(card.body ?? '', encoded),
    decodeIfEncoded(card.front ?? '', encoded),
    decodeIfEncoded(card.back ?? '', encoded),
    decodeIfEncoded(card.code ?? '', encoded),
  ]
    .join('\n')
    .toLowerCase();

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!token) continue;
    if (haystack.indexOf(token) < 0) return false;
  }
  return true;
}

export function getTocCardTitle(card: ReferenceCardData): string {
  const encoded = card.encoded === true;
  if (card.title) {
    return decodeIfEncoded(card.title, encoded);
  }
  if (card.kind === 'qa' && card.front) {
    const front = decodeIfEncoded(card.front, encoded);
    const firstLine = front.split('\n')[0] ?? '';
    return firstLine.substring(0, 50) || card.id;
  }
  if (card.body) {
    const body = decodeIfEncoded(card.body, encoded);
    const firstLine = body.split('\n')[0] ?? '';
    return firstLine.substring(0, 50) || card.id;
  }
  return card.id;
}

export function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}秒`;
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${minutes}分${remainingSeconds}秒`;
}

export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp);
  const month = date.getMonth() + 1;
  const day = date.getDate();
  const hour = date.getHours();
  const minute = date.getMinutes();
  return `${month}/${day} ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`;
}

export function formatDocCount(count: number, lang: 'zh' | 'en'): string {
  if (!Number.isFinite(count) || count < 0) return lang === 'en' ? 'N/A' : '未知';
  return `${Math.floor(count)}`;
}

export function t(lang: 'zh' | 'en', zh: string, en: string): string {
  return lang === 'en' ? en : zh;
}

