import {getTranslations} from 'next-intl/server';
import {Card, Badge} from '@healthcare/ui';

export default async function HomePage() { const t = await getTranslations('home'); return <section className="page"><p className="eyebrow">{t('eyebrow')}</p><h1>{t('title')}</h1><p>{t('body')}</p><Card><Badge>{t('status')}</Badge></Card></section>; }
