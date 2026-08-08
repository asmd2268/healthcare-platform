import Link from 'next/link';
import {getTranslations} from 'next-intl/server';
import {requireInventoryScope, handleInventoryPageError} from '@/features/inventory/page-helpers.server';
import {listRecentInventoryActivity} from '@/features/inventory/activity-repository.server';

export const dynamic = 'force-dynamic';

export default async function InventoryActivityPage({params}: {params: Promise<{locale: string}>}) {
  const {locale} = await params;
  const t = await getTranslations('inventory');
  const scope = await requireInventoryScope(locale);
  try {
    const activity = await listRecentInventoryActivity(scope);
    return <section className="page inventory-page"><nav className="inventory-nav"><Link href={`/${locale}/inventory`}>{t('locations')}</Link><Link href={`/${locale}/inventory/balances`}>{t('balances')}</Link><Link href={`/${locale}/inventory/transfers`}>{t('transfers')}</Link><Link href={`/${locale}/inventory/activity`}>{t('activity')}</Link></nav><header className="inventory-heading"><div><p className="eyebrow">{t('activity')}</p><h1>{t('activityTitle')}</h1><p>{t('activityBody')}</p></div></header>{activity.length === 0 ? <p className="inventory-readonly-note">{t('emptyActivity')}</p> : <div className="inventory-card-grid">{activity.map((event) => <article className="ui-card inventory-detail-record" key={event.id}><strong>{t(`operationTypes.${event.action}`, {defaultValue: event.action})}</strong><Link href={`/${locale}/inventory/transfers/${event.transferId}`}>{t('transferReference', {id: event.transferId.slice(0, 8).toUpperCase()})}</Link><small>{new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {dateStyle: 'medium', timeStyle: 'short'}).format(new Date(event.createdAt))}</small></article>)}</div>}</section>;
  } catch (error) { handleInventoryPageError(error, locale); }
}
