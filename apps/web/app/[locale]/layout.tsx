import {NextIntlClientProvider} from 'next-intl';
import {notFound} from 'next/navigation';
import {locales, type Locale} from '@/i18n';
import {PlatformShell} from '@/components/platform-shell';
import {DocumentLocale} from '@/components/document-locale';

export function generateStaticParams() { return locales.map((locale) => ({locale})); }

export default async function LocaleLayout({children, params}: Readonly<{children: React.ReactNode; params: Promise<{locale: string}>}>) {
  const {locale: requestedLocale} = await params;
  if (!locales.includes(requestedLocale as Locale)) notFound();
  const locale = requestedLocale as Locale;
  const messages = (await import(`@/messages/${locale}.json`)).default;
  return <NextIntlClientProvider locale={locale} messages={messages}><DocumentLocale locale={locale} /><PlatformShell>{children}</PlatformShell></NextIntlClientProvider>;
}
