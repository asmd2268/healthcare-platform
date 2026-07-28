import 'server-only';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';
import {
  InventoryReadRepository,
  deriveReservationRemaining,
  type InventoryBalance,
  type InventoryCapability,
  type InventoryDisposition,
  type InventoryLocation,
  type InventoryLocationKind,
  type InventoryReadGateway,
  type InventoryScope,
  type InventoryTransfer,
  type InventoryTransferDetail
} from './repository';

type DatabaseError = {message: string};
type Result<T> = {data: T | null; error: DatabaseError | null};

const rows = async <T>(query: PromiseLike<Result<T[]>>): Promise<T[]> => {
  const {data, error} = await query;
  if (error) throw new Error('Inventory data is unavailable.');
  return data ?? [];
};

const one = async <T>(query: PromiseLike<Result<T>>): Promise<T | null> => {
  const {data, error} = await query;
  if (error) throw new Error('Inventory data is unavailable.');
  return data;
};

const ids = (values: Array<string | null | undefined>) => [...new Set(values.filter((value): value is string => Boolean(value)))];
const number = (value: number | string | null | undefined) => Number(value ?? 0);

type LocationRow = {id: string; tenant_id: string; organization_id: string; facility_id: string; parent_location_id: string | null; code: string; name_ar: string | null; name_en: string; location_kind: InventoryLocationKind; confidential: boolean; active: boolean};
type ProjectionRow = {id: string; tenant_id: string; organization_id: string; facility_id: string; location_id: string; inventory_item_profile_id: string; batch_id: string | null; recording_channel: string; disposition: InventoryDisposition; quantity_base: number | string; updated_at: string};
type ProfileRow = {id: string; catalog_item_id: string};
type CatalogRow = {id: string; item_name_ar: string | null; item_name_en: string};
type BatchRow = {id: string; lot_number: string | null; lot_status: string; expiry_date: string | null; expiry_status: string};
type ItemUnitRow = {inventory_item_profile_id: string; inventory_unit_id: string};
type UnitRow = {id: string; name_ar: string | null; name_en: string};
type TransferRow = {id: string; tenant_id: string; organization_id: string; facility_id: string; source_location_id: string; destination_root_location_id: string; status: string; created_at: string; updated_at: string};
type LineRow = {id: string; transfer_id: string; inventory_item_profile_id: string; requested_quantity_base: number | string};
type AllocationRow = {id: string; transfer_line_id: string; source_location_id: string; batch_id: string; recording_channel: string; source_disposition: string; planned_quantity_base: number | string};
type ReservationRow = {id: string; transfer_allocation_id: string; quantity_base: number | string; expires_at: string};
type AdjustmentRow = {reservation_id: string; quantity_base: number | string};
type OperationRow = {id: string; transfer_id: string; transfer_allocation_id: string | null; operation_type: string; quantity_base: number | string | null; source_location_id: string | null; destination_location_id: string | null; source_disposition: string | null; destination_disposition: string | null; created_at: string};
type ReceiptRow = {id: string; operation_id: string; destination_location_id: string; quantity_base: number | string; created_at: string};
type EventRow = {id: string; transfer_id: string; action: string; created_at: string};
type ClosureRow = {id: string; transfer_id: string; transfer_line_id: string; transfer_allocation_id: string | null; quantity_base: number | string; reason: string; created_at: string};

class SupabaseInventoryReadGateway implements InventoryReadGateway {
  async canRead(scope: InventoryScope, capability: InventoryCapability) {
    const supabase = await createServerUserSupabaseClient();
    const {data: scopeAllowed, error: scopeError} = await supabase.rpc('scope_allowed', {target_tenant: scope.tenantId, target_organization: scope.organizationId, target_facility: scope.facilityId});
    if (scopeError || !scopeAllowed) return false;
    const permissionKeys = capability === 'inventory'
      ? ['inventory.view', 'inventory.manage_catalog', 'inventory.manage_locations', 'platform.full_access']
      : ['inventory.transfer.view', 'inventory.manage_locations', 'platform.full_access'];
    for (const permissionKey of permissionKeys) {
      const {data, error} = await supabase.rpc('has_platform_permission', {permission_key: permissionKey, target_tenant: scope.tenantId, target_organization: scope.organizationId, target_facility: scope.facilityId});
      if (!error && data) return true;
    }
    return false;
  }

  async listLocations(scope: InventoryScope): Promise<InventoryLocation[]> {
    const supabase = await createServerUserSupabaseClient();
    const data = await rows<LocationRow>(supabase.from('inventory_locations').select('id,tenant_id,organization_id,facility_id,parent_location_id,code,name_ar,name_en,location_kind,confidential,active').eq('tenant_id', scope.tenantId).eq('organization_id', scope.organizationId).eq('facility_id', scope.facilityId).order('code').limit(500) as unknown as PromiseLike<Result<LocationRow[]>>);
    return data.map((row) => ({id: row.id, tenantId: row.tenant_id, organizationId: row.organization_id, facilityId: row.facility_id, parentLocationId: row.parent_location_id, code: row.code, nameAr: row.name_ar, nameEn: row.name_en, kind: row.location_kind, confidential: row.confidential, active: row.active}));
  }

  async listBalances(scope: InventoryScope): Promise<InventoryBalance[]> {
    const supabase = await createServerUserSupabaseClient();
    const projections = await rows<ProjectionRow>(supabase.from('inventory_balance_projections').select('id,tenant_id,organization_id,facility_id,location_id,inventory_item_profile_id,batch_id,recording_channel,disposition,quantity_base,updated_at').eq('tenant_id', scope.tenantId).eq('organization_id', scope.organizationId).eq('facility_id', scope.facilityId).gt('quantity_base', 0).order('updated_at', {ascending: false}).limit(1000) as unknown as PromiseLike<Result<ProjectionRow[]>>);
    const locationIds = ids(projections.map((row) => row.location_id));
    const profileIds = ids(projections.map((row) => row.inventory_item_profile_id));
    const batchIds = ids(projections.map((row) => row.batch_id));
    const locations = locationIds.length ? await rows<LocationRow>(supabase.from('inventory_locations').select('id,tenant_id,organization_id,facility_id,parent_location_id,code,name_ar,name_en,location_kind,confidential,active').in('id', locationIds) as unknown as PromiseLike<Result<LocationRow[]>>) : [];
    const profiles = profileIds.length ? await rows<ProfileRow>(supabase.from('inventory_item_profiles').select('id,catalog_item_id').in('id', profileIds) as unknown as PromiseLike<Result<ProfileRow[]>>) : [];
    const batches = batchIds.length ? await rows<BatchRow>(supabase.from('inventory_batches').select('id,lot_number,lot_status,expiry_date,expiry_status').in('id', batchIds) as unknown as PromiseLike<Result<BatchRow[]>>) : [];
    const itemUnits = profileIds.length ? await rows<ItemUnitRow>(supabase.from('inventory_item_units').select('inventory_item_profile_id,inventory_unit_id').in('inventory_item_profile_id', profileIds).eq('active', true).eq('is_base_unit', true) as unknown as PromiseLike<Result<ItemUnitRow[]>>) : [];
    const catalogs = profiles.length ? await rows<CatalogRow>(supabase.from('catalog_items').select('id,item_name_ar,item_name_en').in('id', ids(profiles.map((row) => row.catalog_item_id))) as unknown as PromiseLike<Result<CatalogRow[]>>) : [];
    const units = itemUnits.length ? await rows<UnitRow>(supabase.from('inventory_units').select('id,name_ar,name_en').in('id', ids(itemUnits.map((row) => row.inventory_unit_id))) as unknown as PromiseLike<Result<UnitRow[]>>) : [];
    const locationById = new Map(locations.map((row) => [row.id, row]));
    const profileById = new Map(profiles.map((row) => [row.id, row]));
    const catalogById = new Map(catalogs.map((row) => [row.id, row]));
    const batchById = new Map(batches.map((row) => [row.id, row]));
    const itemUnitByProfile = new Map(itemUnits.map((row) => [row.inventory_item_profile_id, row]));
    const unitById = new Map(units.map((row) => [row.id, row]));
    return projections.flatMap((row) => {
      const location = locationById.get(row.location_id);
      const profile = profileById.get(row.inventory_item_profile_id);
      const catalog = profile ? catalogById.get(profile.catalog_item_id) : undefined;
      if (!location || !profile || !catalog) return [];
      const batch = row.batch_id ? batchById.get(row.batch_id) : undefined;
      const itemUnit = itemUnitByProfile.get(row.inventory_item_profile_id);
      const unit = itemUnit ? unitById.get(itemUnit.inventory_unit_id) : undefined;
      return [{id: row.id, tenantId: row.tenant_id, organizationId: row.organization_id, facilityId: row.facility_id, locationId: row.location_id, locationCode: location.code, locationNameAr: location.name_ar, locationNameEn: location.name_en, profileId: row.inventory_item_profile_id, itemNameAr: catalog.item_name_ar, itemNameEn: catalog.item_name_en, batchId: row.batch_id, lotNumber: batch?.lot_number ?? null, lotStatus: batch?.lot_status ?? 'not_applicable', expiryDate: batch?.expiry_date ?? null, expiryStatus: batch?.expiry_status ?? 'not_applicable', recordingChannel: row.recording_channel, disposition: row.disposition, quantityBase: number(row.quantity_base), baseUnitAr: unit?.name_ar ?? null, baseUnitEn: unit?.name_en ?? null, updatedAt: row.updated_at}];
    });
  }

  async listTransfers(scope: InventoryScope): Promise<InventoryTransfer[]> {
    const supabase = await createServerUserSupabaseClient();
    const transfers = await rows<TransferRow>(supabase.from('inventory_transfers').select('id,tenant_id,organization_id,facility_id,source_location_id,destination_root_location_id,status,created_at,updated_at').eq('tenant_id', scope.tenantId).eq('organization_id', scope.organizationId).eq('facility_id', scope.facilityId).order('updated_at', {ascending: false}).limit(500) as unknown as PromiseLike<Result<TransferRow[]>>);
    return this.mapTransfers(supabase, transfers);
  }

  private async mapTransfers(supabase: Awaited<ReturnType<typeof createServerUserSupabaseClient>>, transfers: TransferRow[]) {
    const locationIds = ids(transfers.flatMap((row) => [row.source_location_id, row.destination_root_location_id]));
    const locations = locationIds.length ? await rows<LocationRow>(supabase.from('inventory_locations').select('id,tenant_id,organization_id,facility_id,parent_location_id,code,name_ar,name_en,location_kind,confidential,active').in('id', locationIds) as unknown as PromiseLike<Result<LocationRow[]>>) : [];
    const locationById = new Map(locations.map((row) => [row.id, row]));
    return transfers.map((row) => {
      const source = locationById.get(row.source_location_id);
      const destination = locationById.get(row.destination_root_location_id);
      return {id: row.id, tenantId: row.tenant_id, organizationId: row.organization_id, facilityId: row.facility_id, status: row.status, sourceLocationId: row.source_location_id, sourceCode: source?.code ?? '', sourceNameAr: source?.name_ar ?? null, sourceNameEn: source?.name_en ?? '', destinationLocationId: row.destination_root_location_id, destinationCode: destination?.code ?? '', destinationNameAr: destination?.name_ar ?? null, destinationNameEn: destination?.name_en ?? '', createdAt: row.created_at, updatedAt: row.updated_at};
    });
  }

  async getTransferDetail(scope: InventoryScope, transferId: string): Promise<InventoryTransferDetail | null> {
    const supabase = await createServerUserSupabaseClient();
    const transfer = await one<TransferRow>(supabase.from('inventory_transfers').select('id,tenant_id,organization_id,facility_id,source_location_id,destination_root_location_id,status,created_at,updated_at').eq('tenant_id', scope.tenantId).eq('organization_id', scope.organizationId).eq('facility_id', scope.facilityId).eq('id', transferId).maybeSingle() as unknown as PromiseLike<Result<TransferRow>>);
    if (!transfer) return null;
    const [mappedTransfer] = await this.mapTransfers(supabase, [transfer]);
    const lines = await rows<LineRow>(supabase.from('inventory_transfer_lines').select('id,transfer_id,inventory_item_profile_id,requested_quantity_base').eq('transfer_id', transferId).order('created_at') as unknown as PromiseLike<Result<LineRow[]>>);
    const lineIds = ids(lines.map((row) => row.id));
    const profileIds = ids(lines.map((row) => row.inventory_item_profile_id));
    const allocations = lineIds.length ? await rows<AllocationRow>(supabase.from('inventory_transfer_allocations').select('id,transfer_line_id,source_location_id,batch_id,recording_channel,source_disposition,planned_quantity_base').in('transfer_line_id', lineIds).order('created_at') as unknown as PromiseLike<Result<AllocationRow[]>>) : [];
    const allocationIds = ids(allocations.map((row) => row.id));
    const reservations = allocationIds.length ? await rows<ReservationRow>(supabase.from('inventory_reservations').select('id,transfer_allocation_id,quantity_base,expires_at').in('transfer_allocation_id', allocationIds).order('created_at') as unknown as PromiseLike<Result<ReservationRow[]>>) : [];
    const reservationIds = ids(reservations.map((row) => row.id));
    const adjustments = reservationIds.length ? await rows<AdjustmentRow>(supabase.from('inventory_reservation_adjustments').select('reservation_id,quantity_base').in('reservation_id', reservationIds) as unknown as PromiseLike<Result<AdjustmentRow[]>>) : [];
    const operations = await rows<OperationRow>(supabase.from('inventory_transfer_operations').select('id,transfer_id,transfer_allocation_id,operation_type,quantity_base,source_location_id,destination_location_id,source_disposition,destination_disposition,created_at').eq('transfer_id', transferId).order('created_at', {ascending: false}) as unknown as PromiseLike<Result<OperationRow[]>>);
    const operationIds = ids(operations.map((row) => row.id));
    const receipts = operationIds.length ? await rows<ReceiptRow>(supabase.from('inventory_transfer_receipt_destinations').select('id,operation_id,destination_location_id,quantity_base,created_at').in('operation_id', operationIds).order('created_at', {ascending: false}) as unknown as PromiseLike<Result<ReceiptRow[]>>) : [];
    const events = await rows<EventRow>(supabase.from('inventory_transfer_events').select('id,transfer_id,action,created_at').eq('transfer_id', transferId).order('created_at', {ascending: false}).limit(500) as unknown as PromiseLike<Result<EventRow[]>>);
    const closures = await rows<ClosureRow>(supabase.from('inventory_transfer_remainder_closures').select('id,transfer_id,transfer_line_id,transfer_allocation_id,quantity_base,reason,created_at').eq('transfer_id', transferId).order('created_at', {ascending: false}) as unknown as PromiseLike<Result<ClosureRow[]>>);
    const profiles = profileIds.length ? await rows<ProfileRow>(supabase.from('inventory_item_profiles').select('id,catalog_item_id').in('id', profileIds) as unknown as PromiseLike<Result<ProfileRow[]>>) : [];
    const catalogs = profiles.length ? await rows<CatalogRow>(supabase.from('catalog_items').select('id,item_name_ar,item_name_en').in('id', ids(profiles.map((row) => row.catalog_item_id))) as unknown as PromiseLike<Result<CatalogRow[]>>) : [];
    const batches = allocations.length ? await rows<BatchRow>(supabase.from('inventory_batches').select('id,lot_number,lot_status,expiry_date,expiry_status').in('id', ids(allocations.map((row) => row.batch_id))) as unknown as PromiseLike<Result<BatchRow[]>>) : [];
    const locationIds = ids([...allocations.map((row) => row.source_location_id), ...operations.flatMap((row) => [row.source_location_id, row.destination_location_id]), ...receipts.map((row) => row.destination_location_id)]);
    const locations = locationIds.length ? await rows<LocationRow>(supabase.from('inventory_locations').select('id,tenant_id,organization_id,facility_id,parent_location_id,code,name_ar,name_en,location_kind,confidential,active').in('id', locationIds) as unknown as PromiseLike<Result<LocationRow[]>>) : [];
    const profileById = new Map(profiles.map((row) => [row.id, row]));
    const catalogById = new Map(catalogs.map((row) => [row.id, row]));
    const batchById = new Map(batches.map((row) => [row.id, row]));
    const locationById = new Map(locations.map((row) => [row.id, row]));
    const lineById = new Map(lines.map((row) => [row.id, row]));
    const allocationById = new Map(allocations.map((row) => [row.id, row]));
    const operationById = new Map(operations.map((row) => [row.id, row]));
    const adjustedByReservation = new Map<string, number>();
    adjustments.forEach((row) => adjustedByReservation.set(row.reservation_id, (adjustedByReservation.get(row.reservation_id) ?? 0) + number(row.quantity_base)));
    return {
      ...mappedTransfer,
      lines: lines.map((row) => {const profile = profileById.get(row.inventory_item_profile_id); const catalog = profile ? catalogById.get(profile.catalog_item_id) : undefined; return {id: row.id, transferId, profileId: row.inventory_item_profile_id, itemNameAr: catalog?.item_name_ar ?? null, itemNameEn: catalog?.item_name_en ?? '', requestedQuantityBase: number(row.requested_quantity_base)};}),
      allocations: allocations.map((row) => {const location = locationById.get(row.source_location_id); const batch = batchById.get(row.batch_id); return {id: row.id, transferId, lineId: row.transfer_line_id, sourceLocationId: row.source_location_id, sourceCode: location?.code ?? '', batchId: row.batch_id, lotNumber: batch?.lot_number ?? null, plannedQuantityBase: number(row.planned_quantity_base), recordingChannel: row.recording_channel, sourceDisposition: row.source_disposition};}),
      reservations: reservations.map((row) => {const allocation = allocationById.get(row.transfer_allocation_id); const line = allocation ? lineById.get(allocation.transfer_line_id) : undefined; const adjustedQuantityBase = adjustedByReservation.get(row.id) ?? 0; const quantityBase = number(row.quantity_base); return {id: row.id, transferId: line?.transfer_id ?? '', allocationId: row.transfer_allocation_id, quantityBase, adjustedQuantityBase, remainingQuantityBase: deriveReservationRemaining(quantityBase, adjustedQuantityBase), expiresAt: row.expires_at};}),
      operations: operations.map((row) => {const destination = row.destination_location_id ? locationById.get(row.destination_location_id) : undefined; return {id: row.id, transferId: row.transfer_id, allocationId: row.transfer_allocation_id, type: row.operation_type, quantityBase: row.quantity_base === null ? null : number(row.quantity_base), sourceLocationId: row.source_location_id, destinationLocationId: row.destination_location_id, destinationCode: destination?.code ?? null, destinationNameAr: destination?.name_ar ?? null, destinationNameEn: destination?.name_en ?? null, sourceDisposition: row.source_disposition, destinationDisposition: row.destination_disposition, createdAt: row.created_at};}),
      receiptDestinations: receipts.map((row) => {const operation = operationById.get(row.operation_id); const destination = locationById.get(row.destination_location_id); return {id: row.id, transferId: operation?.transfer_id ?? '', operationId: row.operation_id, destinationLocationId: row.destination_location_id, destinationCode: destination?.code ?? '', destinationNameAr: destination?.name_ar ?? null, destinationNameEn: destination?.name_en ?? '', quantityBase: number(row.quantity_base), createdAt: row.created_at};}),
      events: events.map((row) => ({id: row.id, transferId: row.transfer_id, action: row.action, createdAt: row.created_at})),
      closures: closures.map((row) => ({id: row.id, transferId: row.transfer_id, lineId: row.transfer_line_id, allocationId: row.transfer_allocation_id, quantityBase: number(row.quantity_base), reason: row.reason, createdAt: row.created_at}))
    };
  }
}

export const createInventoryReadRepository = () => new InventoryReadRepository(new SupabaseInventoryReadGateway());
