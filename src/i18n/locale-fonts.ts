/**
 * Lazy, self-hosted locale font CSS loader shared by UI-language changes and
 * script-aware user text. Importing this module does not fetch a font shard;
 * each CSS chunk remains behind its dynamic import until it is needed.
 */

import { type LocaleFontCode } from './locale-font-contract.ts';

export { hasLocaleFont } from './locale-font-contract.ts';
export type { LocaleFontCode } from './locale-font-contract.ts';

export function isLocaleFontLoadedForTests(_code: LocaleFontCode): boolean {
  return false;
}

function loadLocaleFont(_code: LocaleFontCode): Promise<void> {
  return Promise.resolve();
}

function preloadLocaleFontGlyphs(_code: LocaleFontCode, _text: string): Promise<boolean> {
  return Promise.resolve(true);
}

export function __setLocaleFontLoaderForTests(_code: LocaleFontCode, _loader: () => Promise<unknown>): void {}

export function __resetLocaleFontLoadingForTests(): void {}

export const loadLocaleFontForTests = loadLocaleFont;
export const preloadLocaleFontGlyphsForTests = preloadLocaleFontGlyphs;

const localeFontRuntime = Object.freeze({ loadLocaleFont, preloadLocaleFontGlyphs });

export default localeFontRuntime;
