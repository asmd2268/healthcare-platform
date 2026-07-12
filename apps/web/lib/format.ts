import type {Locale} from '@/i18n';

export const formatDateTime = (value: Date, locale: Locale) => new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {dateStyle: 'medium', timeStyle: 'short'}).format(value);
