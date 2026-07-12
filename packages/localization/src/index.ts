export const locales = ['ar', 'en'] as const;
export type Locale = (typeof locales)[number];
export const localeDirection: Record<Locale, 'rtl' | 'ltr'> = {ar: 'rtl', en: 'ltr'};
export const isLocale = (value: string): value is Locale => locales.includes(value as Locale);
