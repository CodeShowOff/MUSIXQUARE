/**
 * Exhaustive plural-message catalog for tests and build-time audits.
 *
 * The browser runtime reads each named export from the matching lazy locale
 * module instead, so importing the i18n engine never pulls this aggregate
 * catalog into the production entry chunk.
 */

import type { LanguageCode } from './locales.ts';
import { EN_PLURAL_MESSAGES } from './plural-en.ts';
import type { LocalePluralMessages } from './plural-contract.ts';

export { PLURAL_PARAM_BY_KEY } from './plural-contract.ts';
export type { LocalePluralMessages, PluralCategory, PluralI18nKey } from './plural-contract.ts';

export const pluralMessagesForTests = {
  en: EN_PLURAL_MESSAGES,
} satisfies Partial<Record<LanguageCode, LocalePluralMessages>>;
