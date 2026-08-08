import {InventoryLocationsView} from '@/components/inventory/read-only-workspace';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';

export const dynamic = 'force-dynamic';
export default async function InventoryLocationsPage({params, searchParams}: {params: Promise<{locale: string}>; searchParams: Promise<{q?: string}>}) {
  const [{locale}, {q = ''}] = await Promise.all([params, searchParams]);
  try { const scope = await requireInventoryScope(locale); const locations = await createInventoryReadRepository().listLocations(scope, {query: q}); return <InventoryLocationsView locations={locations} query={q}/>; }
  catch (error) { handleInventoryPageError(error, locale); }
}
