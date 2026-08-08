import 'server-only';
import {createHash} from 'node:crypto';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';
import type {InventoryScope} from './repository';
import {
  emptyTransferCapabilities,
  transferPermission,
  type TransferCapabilities,
  type TransferCapability,
  type TransferMutationAction
} from './mutations';

type DatabaseError = {message: string; code?: string};
type Result<T> = {data: T | null; error: DatabaseError | null};
type JsonRecord = Record<string, unknown>;

export class InventoryMutationError extends Error {
  constructor(public readonly kind: 'invalid' | 'denied' | 'conflict' | 'unavailable') {
    super(`Inventory mutation ${kind}.`);
  }
}

const stableValue = (value: unknown): unknown => {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value as JsonRecord).sort(([a], [b]) => a.localeCompare(b)).map(([key, child]) => [key, stableValue(child)]));
  return value;
};

export const inventoryRequestHash = (value: unknown) => createHash('sha256').update(JSON.stringify(stableValue(value))).digest('hex');

function mapDatabaseError(error: DatabaseError): InventoryMutationError {
  const message = error.message.toLocaleLowerCase();
  if (message.includes('idempotency') || message.includes('conflict')) return new InventoryMutationError('conflict');
  if (message.includes('denied') || error.code === '42501') return new InventoryMutationError('denied');
  if (error.code === '23514' || error.code === '23503' || message.includes('exceeds') || message.includes('negative')) return new InventoryMutationError('invalid');
  return new InventoryMutationError('unavailable');
}

async function requireScope(scope: InventoryScope) {
  const supabase = await createServerUserSupabaseClient();
  const {data, error} = await supabase.rpc('scope_allowed', {target_tenant: scope.tenantId, target_organization: scope.organizationId, target_facility: scope.facilityId}) as unknown as Result<boolean>;
  if (error || !data) throw new InventoryMutationError('denied');
  return supabase;
}

async function hasPermission(scope: InventoryScope, permission: string) {
  const supabase = await createServerUserSupabaseClient();
  const {data, error} = await supabase.rpc('has_platform_permission', {permission_key: permission, target_tenant: scope.tenantId, target_organization: scope.organizationId, target_facility: scope.facilityId}) as unknown as Result<boolean>;
  return !error && Boolean(data);
}

export async function loadTransferCapabilities(scope: InventoryScope): Promise<TransferCapabilities> {
  try { await requireScope(scope); } catch { return emptyTransferCapabilities(); }
  const keys = Object.keys(transferPermission) as TransferCapability[];
  const [permissions, managesLocations] = await Promise.all([
    Promise.all(keys.map(async (key) => [key, await hasPermission(scope, transferPermission[key])] as const)),
    hasPermission(scope, 'inventory.manage_locations')
  ]);
  const capabilities = emptyTransferCapabilities();
  for (const [key, allowed] of permissions) capabilities[key] = allowed;
  capabilities.create = capabilities.create && managesLocations;
  return capabilities;
}

async function requireCapability(scope: InventoryScope, capability: TransferCapability) {
  await requireScope(scope);
  if (!await hasPermission(scope, transferPermission[capability])) throw new InventoryMutationError('denied');
  if (capability === 'create' && !await hasPermission(scope, 'inventory.manage_locations')) throw new InventoryMutationError('denied');
}

async function requireScopedTransfer(scope: InventoryScope, transferId: string) {
  const supabase = await createServerUserSupabaseClient();
  const {data, error} = await supabase.from('inventory_transfers').select('id').eq('tenant_id', scope.tenantId).eq('organization_id', scope.organizationId).eq('facility_id', scope.facilityId).eq('id', transferId).maybeSingle() as unknown as Result<{id: string}>;
  if (error || !data) throw new InventoryMutationError('denied');
}

async function callRpc(name: string, parameters: JsonRecord) {
  const supabase = await createServerUserSupabaseClient();
  const {data, error} = await supabase.rpc(name, parameters) as unknown as Result<string>;
  if (error) throw mapDatabaseError(error);
  if (!data) throw new InventoryMutationError('unavailable');
  return data;
}

export type CreateTransferInput = {
  sourceLocationId: string;
  destinationLocationId: string;
  allocations: Array<{profileId: string; batchId: string; channel: string; quantityBase: number}>;
  idempotencyKey: string;
  reason: string;
};

export async function createTransfer(scope: InventoryScope, input: CreateTransferInput) {
  await requireCapability(scope, 'create');
  const supabase = await createServerUserSupabaseClient();
  const locationChecks = await Promise.all([input.sourceLocationId, input.destinationLocationId].map((locationId) => supabase.rpc('can_manage_inventory_location', {p_location: locationId}) as unknown as Promise<Result<boolean>>));
  if (locationChecks.some(({data, error}) => error || !data)) throw new InventoryMutationError('denied');
  const allocations = input.allocations.map((allocation) => ({profile_id: allocation.profileId, batch_id: allocation.batchId, channel: allocation.channel, quantity_base: allocation.quantityBase}));
  const request = {version: 1, action: 'transfer_create', scope, source: input.sourceLocationId, destination: input.destinationLocationId, allocations, reason: input.reason};
  return callRpc('create_inventory_transfer', {
    p_t: scope.tenantId, p_o: scope.organizationId, p_f: scope.facilityId,
    p_source: input.sourceLocationId, p_destination: input.destinationLocationId,
    p_allocations: allocations, p_key: input.idempotencyKey,
    p_hash: inventoryRequestHash(request), p_reason: input.reason
  });
}

export type TransferMutationInput = {
  action: TransferMutationAction;
  transferId: string;
  lineId?: string;
  allocationId?: string;
  profileId?: string;
  quantityBase?: number;
  destinationLocationId?: string;
  destinationDisposition?: string;
  expiresAt?: string;
  idempotencyKey: string;
  reason?: string;
};

export async function mutateTransfer(scope: InventoryScope, input: TransferMutationInput) {
  await requireCapability(scope, input.action);
  await requireScopedTransfer(scope, input.transferId);
  const base = {version: 1, action: input.action, transferId: input.transferId};
  if (input.action === 'reserve') {
    const payload = {...base, expiresAt: input.expiresAt};
    return callRpc('reserve_inventory_transfer', {p_transfer: input.transferId, p_expires_at: input.expiresAt, p_key: input.idempotencyKey, p_hash: inventoryRequestHash(payload)});
  }
  if (input.action === 'cancel') {
    const payload = {...base, reason: input.reason};
    return callRpc('cancel_inventory_transfer', {p_transfer: input.transferId, p_key: input.idempotencyKey, p_hash: inventoryRequestHash(payload), p_reason: input.reason});
  }
  if (input.action === 'close_remainder') {
    const closures = [{transfer_line_id: input.lineId, transfer_allocation_id: input.allocationId, inventory_item_profile_id: input.profileId, quantity_base: input.quantityBase}];
    return callRpc('close_inventory_transfer_remainder', {p_transfer: input.transferId, p_closures: closures, p_key: input.idempotencyKey, p_reason: input.reason});
  }
  const moves = [{transfer_allocation_id: input.allocationId, quantity_base: input.quantityBase, ...(input.action === 'receive' ? {destination_location_id: input.destinationLocationId, destination_disposition: input.destinationDisposition} : {}), ...(input.action === 'dispose' ? {destination_disposition: input.destinationDisposition} : {})}];
  const payload = {...base, moves, reason: input.reason};
  const rpc = {issue: 'issue_inventory_transfer', receive: 'receive_inventory_transfer', reject: 'reject_inventory_transfer', return: 'return_rejected_inventory_transfer', dispose: 'dispose_rejected_inventory_transfer'}[input.action];
  const parameterName = input.action === 'issue' ? 'p_issues' : input.action === 'receive' ? 'p_receipts' : input.action === 'reject' ? 'p_rejections' : input.action === 'return' ? 'p_returns' : 'p_disposals';
  return callRpc(rpc, {p_transfer: input.transferId, [parameterName]: moves, p_key: input.idempotencyKey, p_hash: inventoryRequestHash(payload), p_reason: input.reason});
}
