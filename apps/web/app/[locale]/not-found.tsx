import Link from 'next/link';
import {getTranslations} from 'next-intl/server';
export default async function NotFound() { const t = await getTranslations('system'); return <section className="page"><h1>{t('notFound')}</h1><Link href="/ar">{t('backHome')}</Link></section>; }
