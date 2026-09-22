import { LANGUAGE_OPTIONS, type LanguageCode } from '../i18n/locales.ts';

const COMPLETION_MARKER = 'mxqr-swu';
const COMPLETION_MESSAGES = {
  en: 'Update applied',
} as const satisfies Readonly<Record<LanguageCode, string>>;

/** Remember a localized completion message across the imminent same-tab navigation. */
export function recordServiceWorkerUpdateCompletion(): void {
  const htmlLanguage = document.documentElement.lang.toLowerCase();
  const language = LANGUAGE_OPTIONS.find(
    ({ code, htmlLang }) => code === htmlLanguage || htmlLang.toLowerCase() === htmlLanguage,
  )?.code;
  try {
    sessionStorage.setItem(COMPLETION_MARKER, COMPLETION_MESSAGES[language ?? 'en']);
  } catch {
    // Storage may be unavailable; the update itself must still complete.
  }
}
