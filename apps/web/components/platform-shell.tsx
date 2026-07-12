'use client';

import Link from 'next/link';
import {useLocale, useTranslations} from 'next-intl';
import {usePathname, useRouter} from 'next/navigation';
import {useEffect, useState} from 'react';
import {defaultBranding} from '@healthcare/branding';
import {Button} from '@healthcare/ui';
import {type Locale} from '@/i18n';
import {useIdleLock} from '@/features/session/use-idle-lock';

export function PlatformShell({children}: {children: React.ReactNode}) {
  const t = useTranslations(); const locale = useLocale() as Locale; const router = useRouter(); const pathname = usePathname();
  const [theme, setTheme] = useState<'light' | 'dark'>('light'); const {locked, lock, unlock} = useIdleLock();
  useEffect(() => { const saved = localStorage.getItem('platform-theme') as 'light' | 'dark' | null; if (saved) setTheme(saved); }, []);
  useEffect(() => { document.documentElement.dataset.theme = theme; localStorage.setItem('platform-theme', theme); }, [theme]);
  const changeLocale = (next: Locale) => { localStorage.setItem('platform-locale', next); router.replace(pathname.replace(`/${locale}`, `/${next}`)); };
  const nav = [['', 'nav.home'], ['inspections', 'inspections.nav'], ['settings', 'nav.settings'], ['profile', 'nav.profile'], ['audit', 'nav.audit']] as const;
  if (locked) return <main className="lock-screen"><h1>{t('shell.lock')}</h1><Button onClick={unlock}>{t('auth.submit')}</Button></main>;
  return <div className="shell"><aside className="sidebar"><strong>{defaultBranding.platformName}</strong><p>{t('shell.organization')}</p><nav>{nav.map(([path, key]) => <Link key={path} href={`/${locale}/${path}`}>{t(key)}</Link>)}</nav></aside><main className="main"><header className="header"><span>{defaultBranding.showDeveloperAttribution ? defaultBranding.reportFooter : ''}</span><div className="controls"><select aria-label={t('shell.language')} value={locale} onChange={(event) => changeLocale(event.target.value as Locale)}><option value="ar">العربية</option><option value="en">English</option></select><Button onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}>{t('shell.theme')}</Button><Button onClick={lock}>{t('shell.lock')}</Button><span aria-label={t('shell.notifications')}>◌</span></div></header>{children}</main></div>;
}
