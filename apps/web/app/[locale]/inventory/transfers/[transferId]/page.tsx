import {InventoryTransferDetailView} from '@/components/inventory/read-only-workspace';
import {handleInventoryPageError, requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {createInventoryReadRepository} from '@/features/inventory/supabase-repository.server';

export const dynamic = 'force-dynamic';
export default async function InventoryTransferDetailPage({params}: {params: Promise<{locale: string; transferId: string}>}) {
  const {locale, transferId} = await params;
  try { const scope = await requireInventoryScope(locale); const transfer = await createInventoryReadRepository().getTransferDetail(scope, transferId); return <InventoryTransferDetailView transfer={transfer}/>; }
  catch (error) { handleInventoryPageError(error, locale); }
}
