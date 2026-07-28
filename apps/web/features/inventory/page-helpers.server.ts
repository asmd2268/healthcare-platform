import 'server-only';
import {notFound, redirect} from 'next/navigation';
import {getCurrentTenantContext} from '@/lib/tenant-context.server';
import {InventoryAuthorizationError, InventoryNotFoundError, type InventoryScope} from './repository';

export async function requireInventoryScope(locale: string): Promise<InventoryScope> {
  const context = await getCurrentTenantContext();
  if (!context?.organizationId || !context.facilityId) redirect(`/${locale}/unauthorized`);
  return {tenantId: context.tenantId, organizationId: context.organizationId, facilityId: context.facilityId};
}

export function handleInventoryPageError(error: unknown, locale: string): never {
  if (error instanceof InventoryAuthorizationError) redirect(`/${locale}/unauthorized`);
  if (error instanceof InventoryNotFoundError) notFound();
  throw error;
}
