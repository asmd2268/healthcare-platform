import {getTranslations} from 'next-intl/server';
export default async function UnauthorizedPage() { const t = await getTranslations('system'); return <section className="page"><h1>{t('unauthorized')}</h1></section>; }
