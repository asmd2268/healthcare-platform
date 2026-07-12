import {getRequestConfig} from 'next-intl/server';
import {defaultLocale, locales, type Locale} from '@/i18n';

export default getRequestConfig(async ({requestLocale}) => {
  const requestedLocale = await requestLocale;
  const locale = locales.includes(requestedLocale as Locale) ? requestedLocale as Locale : defaultLocale;
  return {locale, messages: (await import(`@/messages/${locale}.json`)).default};
});
