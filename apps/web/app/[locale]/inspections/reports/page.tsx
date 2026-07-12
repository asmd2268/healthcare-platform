import {getTranslations} from 'next-intl/server';
export default async function ReportsPage(){const t=await getTranslations('inspections.reports');return <section className="page"><h1>{t('title')}</h1><p>{t('placeholder')}</p><h2>{t('summary')}</h2><h2>{t('history')}</h2></section>}
