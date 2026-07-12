import {getTranslations} from 'next-intl/server';
import {Alert} from '@healthcare/ui';
export default async function AuditPage() { const t = await getTranslations('audit'); return <section className="page"><h1>{t('title')}</h1><p>{t('body')}</p><Alert>{t('placeholder')}</Alert></section>; }
