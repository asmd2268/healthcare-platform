export type InventoryScope = {
  tenantId: string;
  organizationId: string;
  facilityId: string;
};

export type InventoryLocationKind = 'storage' | 'department' | 'pharmacy' | 'controlled' | 'transit';
export type InventoryDisposition = 'available' | 'reserved' | 'quarantine' | 'damaged' | 'expired' | 'returns_hold' | 'wastage_hold' | 'transit';

export type InventoryLocation = InventoryScope & {
  id: string;
  parentLocationId: string | null;
  code: string;
  nameAr: string | null;
  nameEn: string;
  kind: InventoryLocationKind;
  confidential: boolean;
  active: boolean;
};

export type InventoryBalance = InventoryScope & {
  id: string;
  locationId: string;
  locationCode: string;
  locationNameAr: string | null;
  locationNameEn: string;
  profileId: string;
  itemNameAr: string | null;
  itemNameEn: string;
  batchId: string | null;
  lotNumber: string | null;
  lotStatus: string;
  expiryDate: string | null;
  expiryStatus: string;
  recordingChannel: string;
  disposition: InventoryDisposition;
  quantityBase: number;
  baseUnitAr: string | null;
  baseUnitEn: string | null;
  updatedAt: string;
};

export type InventoryTransfer = InventoryScope & {
  id: string;
  status: string;
  sourceLocationId: string;
  sourceCode: string;
  sourceNameAr: string | null;
  sourceNameEn: string;
  destinationLocationId: string;
  destinationCode: string;
  destinationNameAr: string | null;
  destinationNameEn: string;
  createdAt: string;
  updatedAt: string;
};

export type TransferLine = {id: string; transferId: string; profileId: string; itemNameAr: string | null; itemNameEn: string; requestedQuantityBase: number};
export type TransferAllocation = {id: string; transferId: string; lineId: string; sourceLocationId: string; sourceCode: string; batchId: string; lotNumber: string | null; plannedQuantityBase: number; recordingChannel: string; sourceDisposition: string};
export type TransferReservation = {id: string; transferId: string; allocationId: string; quantityBase: number; adjustedQuantityBase: number; remainingQuantityBase: number; expiresAt: string};
export type TransferOperation = {id: string; transferId: string; allocationId: string | null; type: string; quantityBase: number | null; sourceLocationId: string | null; destinationLocationId: string | null; destinationCode: string | null; destinationNameAr: string | null; destinationNameEn: string | null; sourceDisposition: string | null; destinationDisposition: string | null; createdAt: string};
export type TransferReceiptDestination = {id: string; transferId: string; operationId: string; destinationLocationId: string; destinationCode: string; destinationNameAr: string | null; destinationNameEn: string | null; quantityBase: number; createdAt: string};
export type TransferEvent = {id: string; transferId: string; action: string; createdAt: string};
export type TransferClosure = {id: string; transferId: string; lineId: string; allocationId: string | null; quantityBase: number; reason: string; createdAt: string};

export type InventoryTransferDetail = InventoryTransfer & {
  lines: TransferLine[];
  allocations: TransferAllocation[];
  reservations: TransferReservation[];
  operations: TransferOperation[];
  receiptDestinations: TransferReceiptDestination[];
  events: TransferEvent[];
  closures: TransferClosure[];
};

export type InventoryFilters = {query?: string; locationId?: string; disposition?: string; status?: string};
export type InventoryCapability = 'inventory' | 'transfers';

export interface InventoryReadGateway {
  canRead(scope: InventoryScope, capability: InventoryCapability): Promise<boolean>;
  listLocations(scope: InventoryScope): Promise<InventoryLocation[]>;
  listBalances(scope: InventoryScope): Promise<InventoryBalance[]>;
  listTransfers(scope: InventoryScope): Promise<InventoryTransfer[]>;
  getTransferDetail(scope: InventoryScope, transferId: string): Promise<InventoryTransferDetail | null>;
}

export class InventoryAuthorizationError extends Error {
  constructor() { super('Inventory read authorization denied.'); }
}

export class InventoryNotFoundError extends Error {
  constructor() { super('Inventory record was not found.'); }
}

const inScope = (row: InventoryScope, scope: InventoryScope) => row.tenantId === scope.tenantId && row.organizationId === scope.organizationId && row.facilityId === scope.facilityId;
const normalize = (value: string | undefined) => value?.trim().toLocaleLowerCase() ?? '';
const includes = (values: Array<string | null | undefined>, query: string) => values.some((value) => value?.toLocaleLowerCase().includes(query));
export const deriveReservationRemaining = (quantityBase: number, adjustedQuantityBase: number) => Math.max(0, quantityBase - adjustedQuantityBase);

export class InventoryReadRepository {
  constructor(private readonly gateway: InventoryReadGateway) {}

  private async authorize(scope: InventoryScope, capability: InventoryCapability) {
    if (!await this.gateway.canRead(scope, capability)) throw new InventoryAuthorizationError();
  }

  async listLocations(scope: InventoryScope, filters: InventoryFilters = {}) {
    await this.authorize(scope, 'inventory');
    const query = normalize(filters.query);
    return (await this.gateway.listLocations(scope))
      .filter((row) => inScope(row, scope))
      .filter((row) => !query || includes([row.code, row.nameAr, row.nameEn, row.kind], query));
  }

  async listBalances(scope: InventoryScope, filters: InventoryFilters = {}) {
    await this.authorize(scope, 'inventory');
    const query = normalize(filters.query);
    return (await this.gateway.listBalances(scope))
      .filter((row) => inScope(row, scope))
      .filter((row) => !filters.locationId || row.locationId === filters.locationId)
      .filter((row) => !filters.disposition || row.disposition === filters.disposition)
      .filter((row) => !query || includes([row.locationCode, row.locationNameAr, row.locationNameEn, row.itemNameAr, row.itemNameEn, row.lotNumber], query));
  }

  async listTransfers(scope: InventoryScope, filters: InventoryFilters = {}) {
    await this.authorize(scope, 'transfers');
    const query = normalize(filters.query);
    return (await this.gateway.listTransfers(scope))
      .filter((row) => inScope(row, scope))
      .filter((row) => !filters.status || row.status === filters.status)
      .filter((row) => !query || includes([row.id, row.status, row.sourceCode, row.sourceNameAr, row.sourceNameEn, row.destinationCode, row.destinationNameAr, row.destinationNameEn], query));
  }

  async getTransferDetail(scope: InventoryScope, transferId: string) {
    await this.authorize(scope, 'transfers');
    const detail = await this.gateway.getTransferDetail(scope, transferId);
    if (!detail || !inScope(detail, scope)) throw new InventoryNotFoundError();
    return {
      ...detail,
      lines: detail.lines.filter((row) => row.transferId === detail.id),
      allocations: detail.allocations.filter((row) => row.transferId === detail.id),
      reservations: detail.reservations.filter((row) => row.transferId === detail.id),
      operations: detail.operations.filter((row) => row.transferId === detail.id),
      receiptDestinations: detail.receiptDestinations.filter((row) => row.transferId === detail.id),
      events: detail.events.filter((row) => row.transferId === detail.id),
      closures: detail.closures.filter((row) => row.transferId === detail.id)
    };
  }
}
