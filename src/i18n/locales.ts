export const LANGUAGE_OPTIONS = [
  {
    code: 'en',
    htmlLang: 'en',
    nativeName: 'English',
    englishName: 'Default',
  },
] as const;

export type LanguageCode = (typeof LANGUAGE_OPTIONS)[number]['code'];



export function languageDirection(_code: LanguageCode): 'ltr' | 'rtl' {
  return 'ltr';
}

export function localizedAppPath(_code: LanguageCode): string {
  return '/';
}

export function localizedAppEntryPath(_code: LanguageCode): string {
  return `/${_code}/`;
}

export function localizedAboutPath(_code: LanguageCode): string {
  return '/about';
}

/** Explicit About language entry; English retains `/about` as its SEO canonical. */
export function localizedAboutEntryPath(_code: LanguageCode): string {
  return `/${_code}/about`;
}

export function appLanguageFromPathname(_pathname: string): LanguageCode | null {
  return 'en';
}
