import {getTranslations} from 'next-intl/server';
export default async function ProfilePage() { const t = await getTranslations('profile'); return <section className="page"><h1>{t('title')}</h1><p>{t('body')}</p></section>; }
