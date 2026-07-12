'use client';

import {useEffect} from 'react';
import {localeDirection, type Locale} from '@/i18n';

/** Keeps the single root document element aligned with the active locale. */
export function DocumentLocale({locale}: {locale: Locale}) {
  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = localeDirection[locale];
  }, [locale]);
  return null;
}
