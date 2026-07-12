import {NextIntlClientProvider} from 'next-intl';
import {notFound} from 'next/navigation';
import {localeDirection, locales, type Locale} from '@/i18n';
import {PlatformShell} from '@/components/platform-shell';

export function generateStaticParams() { return locales.map((locale) => ({locale})); }

export default async function LocaleLayout({children, params}: Readonly<{children: React.ReactNode; params: Promise<{locale: string}>}>) {
  const {locale: requestedLocale} = await params;
  if (!locales.includes(requestedLocale as Locale)) notFound();
  const locale = requestedLocale as Locale;
  const messages = (await import(`@/messages/${locale}.json`)).default;
  return <html lang={locale} dir={localeDirection[locale]}><body><NextIntlClientProvider locale={locale} messages={messages}><PlatformShell>{children}</PlatformShell></NextIntlClientProvider></body></html>;
}
