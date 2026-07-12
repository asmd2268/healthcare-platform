'use client';
import {useTranslations} from 'next-intl';
export default function ErrorPage() { const t = useTranslations('system'); return <section className="page"><h1>{t('error')}</h1></section>; }
