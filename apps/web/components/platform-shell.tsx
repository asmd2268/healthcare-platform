'use client';

import Link from 'next/link';
import {useLocale, useTranslations} from 'next-intl';
import {usePathname, useRouter} from 'next/navigation';
import {useEffect, useState} from 'react';
import {localizedBranding} from '@healthcare/branding';
import type {ModuleKey} from '@healthcare/licensing';
import {Button} from '@healthcare/ui';
import {type Locale} from '@/i18n';
import {useIdleLock} from '@/features/session/use-idle-lock';
import {signOutAction} from '@/app/[locale]/login/actions';
import type {PlatformExperience} from '@/lib/commercial-types';

export function PlatformShell({children,experience}: {children: React.ReactNode;experience:PlatformExperience}) {
  const t = useTranslations(); const locale = useLocale() as Locale; const router = useRouter(); const pathname = usePathname();
  const [theme, setTheme] = useState<'light' | 'dark'>('light'); const {locked, lock, unlock} = useIdleLock();
  useEffect(() => { const saved = localStorage.getItem('platform-theme') as 'light' | 'dark' | null; if (saved) setTheme(saved); }, []);
  useEffect(() => { document.documentElement.dataset.theme = theme; localStorage.setItem('platform-theme', theme); }, [theme]);
  const changeLocale = (next: Locale) => { localStorage.setItem('platform-locale', next); router.replace(pathname.replace(`/${locale}`, `/${next}`)); };
  const brand=localizedBranding(experience.branding,locale);
  const nav:ReadonlyArray<readonly [string,string,ModuleKey]> = [['','nav.home','core'],['inventory','inventory.nav','inventory'],['inspections','inspections.nav','inspections'],['medication-errors','medicationErrors.nav','medication_errors'],['policies','policies.nav','policies'],['capa','capa.nav','capa'],['settings','nav.settings','core'],['profile','nav.profile','core'],['audit','nav.audit','audit']];
  if (locked) return <main className="lock-screen"><h1>{t('shell.lock')}</h1><Button onClick={unlock}>{t('auth.submit')}</Button></main>;
  const style={'--accent':experience.branding.accentColor,'--brand-primary':experience.branding.primaryColor} as React.CSSProperties;
  return <div className="shell" style={style}><aside className="sidebar"><div className="brand-lockup">{experience.branding.logoUrl?<img src={experience.branding.logoUrl} alt="" className="brand-logo"/>:null}<div><strong>{brand.platformName}</strong><p>{brand.organizationName}</p></div></div><nav>{nav.filter(([, ,module])=>experience.enabledModules.includes(module)).map(([path,key])=><Link key={path||'home'} href={`/${locale}/${path}`}>{t(key)}</Link>)}</nav></aside><main className="main"><header className="header"><span>{experience.branding.showDeveloperAttribution ? brand.reportFooter : ''}</span><div className="controls"><select aria-label={t('shell.language')} value={locale} onChange={(event) => changeLocale(event.target.value as Locale)}><option value="ar">العربية</option><option value="en">English</option></select><Button onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}>{t('shell.theme')}</Button><Button onClick={lock}>{t('shell.lock')}</Button><form action={signOutAction}><input type="hidden" name="locale" value={locale}/><Button type="submit">{t('shell.signOut')}</Button></form><span aria-label={t('shell.notifications')}>◌</span></div></header>{children}</main></div>;
}
