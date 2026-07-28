import {InventoryBalancesView} from '@/components/inventory/read-only-workspace';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';

export const dynamic = 'force-dynamic';
export default async function InventoryBalancesPage({params, searchParams}: {params: Promise<{locale: string}>; searchParams: Promise<{q?: string; location?: string; disposition?: string}>}) {
  const [{locale}, filters] = await Promise.all([params, searchParams]);
  const query = filters.q ?? ''; const locationId = filters.location ?? ''; const disposition = filters.disposition ?? '';
  try { const scope = await requireInventoryScope(locale); const repository = createInventoryReadRepository(); const [balances, locations] = await Promise.all([repository.listBalances(scope, {query, locationId, disposition}), repository.listLocations(scope)]); return <InventoryBalancesView balances={balances} locations={locations} filters={{query, locationId, disposition}}/>; }
  catch (error) { handleInventoryPageError(error, locale); }
}
