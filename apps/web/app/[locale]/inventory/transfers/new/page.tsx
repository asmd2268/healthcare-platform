import Link from 'next/link';
import {getTranslations} from 'next-intl/server';
import {CreateTransferForm} from '@/components/inventory/create-transfer-form';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';
import {loadTransferCapabilities} from '@/features/inventory/mutation-repository.server';
import {redirect} from 'next/navigation';

export const dynamic = 'force-dynamic';

export default async function NewInventoryTransferPage({params}: {params: Promise<{locale: string}>}) {
  const {locale} = await params;
  const t = await getTranslations('inventory');
  const scope = await requireInventoryScope(locale);
  const capabilities = await loadTransferCapabilities(scope);
  if (!capabilities.create) redirect(`/${locale}/unauthorized`);
  try {
    const repository = createInventoryReadRepository();
    const [locations, balances] = await Promise.all([repository.listLocations(scope), repository.listBalances(scope)]);
    return <section className="page inventory-page"><nav className="inventory-nav"><Link href={`/${locale}/inventory`}>{t('locations')}</Link><Link href={`/${locale}/inventory/balances`}>{t('balances')}</Link><Link href={`/${locale}/inventory/transfers`}>{t('transfers')}</Link></nav><Link className="inventory-back" href={`/${locale}/inventory/transfers`}>{t('backToTransfers')}</Link><header className="inventory-heading"><div><p className="eyebrow">{t('transfers')}</p><h1>{t('createTransfer')}</h1><p>{t('createTransferBody')}</p></div></header><CreateTransferForm locations={locations} balances={balances}/></section>;
  } catch (error) { handleInventoryPageError(error, locale); }
}
