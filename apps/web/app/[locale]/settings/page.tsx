import {getTranslations} from 'next-intl/server';
export default async function SettingsPage() { const t = await getTranslations('settings'); return <section className="page"><h1>{t('title')}</h1><p>{t('body')}</p></section>; }
