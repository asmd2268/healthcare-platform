import {InventoryTransfersView} from '@/components/inventory/read-only-workspace';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';

export const dynamic = 'force-dynamic';
export default async function InventoryTransfersPage({params, searchParams}: {params: Promise<{locale: string}>; searchParams: Promise<{q?: string; status?: string}>}) {
  const [{locale}, filters] = await Promise.all([params, searchParams]);
  const query = filters.q ?? ''; const status = filters.status ?? '';
  try { const scope = await requireInventoryScope(locale); const transfers = await createInventoryReadRepository().listTransfers(scope, {query, status}); return <InventoryTransfersView transfers={transfers} filters={{query, status}}/>; }
  catch (error) { handleInventoryPageError(error, locale); }
}
