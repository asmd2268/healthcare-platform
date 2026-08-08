import {InventoryTransferDetailView} from '@/components/inventory/read-only-workspace';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';
import {loadTransferCapabilities} from '@/features/inventory/mutation-repository.server';

export const dynamic = 'force-dynamic';
export default async function InventoryTransferDetailPage({params}: {params: Promise<{locale: string; transferId: string}>}) {
  const {locale, transferId} = await params;
  try { const scope = await requireInventoryScope(locale); const repository = createInventoryReadRepository(); const [transfer, locations, capabilities] = await Promise.all([repository.getTransferDetail(scope, transferId), repository.listLocations(scope), loadTransferCapabilities(scope)]); return <InventoryTransferDetailView transfer={transfer} locations={locations} capabilities={capabilities}/>; }
  catch (error) { handleInventoryPageError(error, locale); }
}
