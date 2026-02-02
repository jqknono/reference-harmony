export type PageBackHandler = () => boolean;

let quizHandler: PageBackHandler | null = null;
let customListHandler: PageBackHandler | null = null;

export function setQuizBackHandler(handler: PageBackHandler | null): void {
  quizHandler = typeof handler === 'function' ? handler : null;
}

export function clearQuizBackHandler(): void {
  quizHandler = null;
}

export function handleQuizBackPress(): boolean {
  try {
    return quizHandler?.() === true;
  } catch (_) {
    return false;
  }
}

export function setCustomListBackHandler(handler: PageBackHandler | null): void {
  customListHandler = typeof handler === 'function' ? handler : null;
}

export function clearCustomListBackHandler(): void {
  customListHandler = null;
}

export function handleCustomListBackPress(): boolean {
  try {
    return customListHandler?.() === true;
  } catch (_) {
    return false;
  }
}
