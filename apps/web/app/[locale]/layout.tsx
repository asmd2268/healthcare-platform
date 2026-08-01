import {NextIntlClientProvider} from 'next-intl';
import {notFound} from 'next/navigation';
import {locales, type Locale} from '@/i18n';
import {PlatformShell} from '@/components/platform-shell';
import {DocumentLocale} from '@/components/document-locale';
import {headers} from 'next/headers';
import {loadPlatformExperience} from '@/lib/commercial.server';
import {localizedBranding} from '@healthcare/branding';
import type {Metadata} from 'next';

export function generateStaticParams() { return locales.map((locale) => ({locale})); }

export async function generateMetadata({params}:{params:Promise<{locale:string}>}):Promise<Metadata>{
  const {locale:requestedLocale}=await params;
  const locale=locales.includes(requestedLocale as Locale)?requestedLocale as Locale:'ar';
  const hostname=(await headers()).get('host');
  const experience=await loadPlatformExperience(hostname);
  const brand=localizedBranding(experience.branding,locale);
  return {title:brand.platformName,description:brand.organizationName,icons:experience.branding.faviconUrl?{icon:experience.branding.faviconUrl}:undefined};
}

export default async function LocaleLayout({children, params}: Readonly<{children: React.ReactNode; params: Promise<{locale: string}>}>) {
  const {locale: requestedLocale} = await params;
  if (!locales.includes(requestedLocale as Locale)) notFound();
  const locale = requestedLocale as Locale;
  const messages = (await import(`@/messages/${locale}.json`)).default;
  const hostname=(await headers()).get('host');
  const experience=await loadPlatformExperience(hostname);
  return <NextIntlClientProvider locale={locale} messages={messages}><DocumentLocale locale={locale} /><PlatformShell experience={experience}>{children}</PlatformShell></NextIntlClientProvider>;
}
