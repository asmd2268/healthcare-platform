import {describe, expect, it} from 'vitest';
import {deriveAllocationProgress, emptyTransferCapabilities, transferPermission} from '@/features/inventory/mutations';
import {inventoryRequestHash} from '@/features/inventory/mutation-repository.server';

describe('inventory transfer operations', () => {
  it('hashes equivalent request objects deterministically', () => {
    expect(inventoryRequestHash({b: 2, a: 1})).toBe(inventoryRequestHash({a: 1, b: 2}));
    expect(inventoryRequestHash({a: 1})).not.toBe(inventoryRequestHash({a: 2}));
  });

  it('derives remaining quantities from immutable allocation evidence', () => {
    const progress = deriveAllocationProgress({
      lines: [{id: 'line-1', transferId: 'transfer-1', profileId: 'profile-1', itemNameAr: 'صنف', itemNameEn: 'Item', requestedQuantityBase: 10}],
      allocations: [{id: 'allocation-1', transferId: 'transfer-1', lineId: 'line-1', sourceLocationId: 'source', sourceCode: 'SRC', batchId: 'batch-1', lotNumber: null, plannedQuantityBase: 10, recordingChannel: 'manual', sourceDisposition: 'available'}],
      operations: [
        {id: 'op-1', allocationId: 'allocation-1', type: 'issue', quantityBase: 4},
        {id: 'op-2', allocationId: 'allocation-1', type: 'receive', quantityBase: 2},
        {id: 'op-3', allocationId: 'allocation-1', type: 'reject', quantityBase: 1}
      ],
      reservations: [{id: 'reservation-1', allocationId: 'allocation-1', remainingQuantityBase: 6}],
      closures: [{id: 'closure-1', allocationId: 'allocation-1', quantityBase: 1}]
    } as never);
    expect(progress[0]).toMatchObject({issued: 4, received: 2, rejected: 1, closed: 1, issueRemaining: 5, transitRemaining: 1, closeRemaining: 5});
  });

  it('defaults every capability to false and maps each action to a permission', () => {
    expect(Object.values(emptyTransferCapabilities()).every(Boolean)).toBe(false);
    expect(transferPermission.close_remainder).toBe('inventory.transfer.close_remainder');
    expect(transferPermission.dispose).toBe('inventory.transfer.dispose');
  });
});
