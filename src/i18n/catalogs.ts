/**
 * Complete translation catalog for build-time rendering and exhaustive tests.
 *
 * The browser runtime deliberately keeps using lazy imports from `index.ts` so
 * adding locales here never folds every dictionary into the initial app bundle.
 */

import en from './en.ts';

import type { LanguageCode } from './locales.ts';

export type TranslationDictionary = Readonly<Record<string, string>>;

export const APP_DICTIONARIES = {
  en,
} as const satisfies Readonly<Record<LanguageCode, TranslationDictionary>>;
