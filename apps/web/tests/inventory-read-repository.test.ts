import {describe, expect, it, vi} from 'vitest';
import {InventoryAuthorizationError, InventoryReadRepository, deriveReservationRemaining, type InventoryReadGateway, type InventoryScope} from '@/features/inventory/repository';

const scope: InventoryScope = {tenantId: 'tenant-a', organizationId: 'org-a', facilityId: 'facility-a'};
const otherScope: InventoryScope = {tenantId: 'tenant-b', organizationId: 'org-b', facilityId: 'facility-b'};

const gateway = (allowed = true): InventoryReadGateway => ({
  canRead: vi.fn().mockResolvedValue(allowed),
  listLocations: vi.fn().mockResolvedValue([
    {...scope, id: 'allowed', parentLocationId: null, code: 'PHARM', nameAr: 'الصيدلية', nameEn: 'Pharmacy', kind: 'pharmacy', confidential: false, active: true},
    {...otherScope, id: 'cross-tenant', parentLocationId: null, code: 'OTHER', nameAr: null, nameEn: 'Other', kind: 'storage', confidential: false, active: true}
  ]),
  listBalances: vi.fn().mockResolvedValue([]),
  listTransfers: vi.fn().mockResolvedValue([]),
  getTransferDetail: vi.fn().mockResolvedValue(null)
});

describe('inventory read repository', () => {
  it('fails closed before issuing a data read when authorization is denied', async () => {
    const denied = gateway(false);
    await expect(new InventoryReadRepository(denied).listLocations(scope)).rejects.toBeInstanceOf(InventoryAuthorizationError);
    expect(denied.listLocations).not.toHaveBeenCalled();
  });

  it('defensively removes cross-tenant rows returned by a gateway', async () => {
    const result = await new InventoryReadRepository(gateway()).listLocations(scope);
    expect(result.map((row) => row.id)).toEqual(['allowed']);
  });

  it('filters bilingual location data without changing the source rows', async () => {
    const source = gateway();
    const result = await new InventoryReadRepository(source).listLocations(scope, {query: 'صيد'});
    expect(result).toHaveLength(1);
    expect(result[0].code).toBe('PHARM');
  });

  it('derives reservation remaining without returning a negative quantity', () => {
    expect(deriveReservationRemaining(10, 4)).toBe(6);
    expect(deriveReservationRemaining(10, 12)).toBe(0);
  });
});
