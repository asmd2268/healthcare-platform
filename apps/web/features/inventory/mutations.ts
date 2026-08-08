import type {InventoryTransferDetail} from './repository';

export const transferMutationActions = [
  'reserve', 'issue', 'receive', 'reject', 'return', 'dispose', 'cancel', 'close_remainder'
] as const;

export type TransferMutationAction = (typeof transferMutationActions)[number];
export type TransferCapability = 'create' | TransferMutationAction;
export type TransferCapabilities = Record<TransferCapability, boolean>;

export const transferPermission: Record<TransferCapability, string> = {
  create: 'inventory.transfer.create',
  reserve: 'inventory.transfer.reserve',
  issue: 'inventory.transfer.issue',
  receive: 'inventory.transfer.receive',
  reject: 'inventory.transfer.reject',
  return: 'inventory.transfer.return',
  dispose: 'inventory.transfer.dispose',
  cancel: 'inventory.transfer.cancel',
  close_remainder: 'inventory.transfer.close_remainder'
};

export const emptyTransferCapabilities = (): TransferCapabilities => ({
  create: false, reserve: false, issue: false, receive: false, reject: false,
  return: false, dispose: false, cancel: false, close_remainder: false
});

export type AllocationProgress = {
  allocationId: string;
  lineId: string;
  profileId: string;
  planned: number;
  reservationRemaining: number;
  issued: number;
  received: number;
  rejected: number;
  returned: number;
  disposed: number;
  closed: number;
  issueRemaining: number;
  transitRemaining: number;
  rejectedRemaining: number;
  closeRemaining: number;
};

const sum = (values: Array<number | null>) => values.reduce<number>((total, value) => total + (value ?? 0), 0);

export function deriveAllocationProgress(transfer: InventoryTransferDetail): AllocationProgress[] {
  return transfer.allocations.map((allocation) => {
    const line = transfer.lines.find((candidate) => candidate.id === allocation.lineId);
    const operations = transfer.operations.filter((operation) => operation.allocationId === allocation.id);
    const issued = sum(operations.filter((operation) => operation.type === 'issue').map((operation) => operation.quantityBase));
    const received = sum(operations.filter((operation) => operation.type === 'receive').map((operation) => operation.quantityBase));
    const rejected = sum(operations.filter((operation) => operation.type === 'reject').map((operation) => operation.quantityBase));
    const returned = sum(operations.filter((operation) => operation.type === 'return').map((operation) => operation.quantityBase));
    const disposed = sum(operations.filter((operation) => operation.type === 'dispose_rejected').map((operation) => operation.quantityBase));
    const closed = sum(transfer.closures.filter((closure) => closure.allocationId === allocation.id).map((closure) => closure.quantityBase));
    const reservationRemaining = sum(transfer.reservations.filter((reservation) => reservation.allocationId === allocation.id).map((reservation) => reservation.remainingQuantityBase));
    return {
      allocationId: allocation.id,
      lineId: allocation.lineId,
      profileId: line?.profileId ?? '',
      planned: allocation.plannedQuantityBase,
      reservationRemaining,
      issued,
      received,
      rejected,
      returned,
      disposed,
      closed,
      issueRemaining: Math.max(0, Math.min(reservationRemaining, allocation.plannedQuantityBase - issued - closed)),
      transitRemaining: Math.max(0, issued - received - rejected),
      rejectedRemaining: Math.max(0, rejected - returned - disposed),
      closeRemaining: Math.max(0, Math.min(reservationRemaining, allocation.plannedQuantityBase - issued - closed))
    };
  });
}
