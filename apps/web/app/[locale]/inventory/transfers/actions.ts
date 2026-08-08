'use server';

import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {requireInventoryScope} from '@/features/inventory/page-helpers.server';
import {InventoryMutationError, createTransfer, mutateTransfer} from '@/features/inventory/mutation-repository.server';
import {transferMutationActions} from '@/features/inventory/mutations';

export type InventoryMutationActionState = {
  status: 'idle' | 'success' | 'invalid' | 'denied' | 'conflict' | 'unavailable';
  action?: string;
  transferId?: string;
};

const localeSchema = z.enum(['ar', 'en']);
const idempotencyKey = z.string().uuid();
const reason = z.string().trim().min(3).max(500);
const positiveQuantity = z.coerce.number().finite().positive().max(1_000_000_000_000);
const confirmation = z.literal('true');

const parseAllocations = z.preprocess((value) => {
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}, z.array(z.object({profileId: z.string().uuid(), batchId: z.string().uuid(), channel: z.string().min(1).max(80), quantityBase: positiveQuantity})).min(1).max(100));

const createSchema = z.object({
  locale: localeSchema,
  sourceLocationId: z.string().uuid(),
  destinationLocationId: z.string().uuid(),
  allocations: parseAllocations,
  idempotencyKey,
  reason,
  confirm: confirmation
});

const mutationSchema = z.object({
  locale: localeSchema,
  action: z.enum(transferMutationActions),
  transferId: z.string().uuid(),
  lineId: z.string().uuid().optional(),
  allocationId: z.string().uuid().optional(),
  profileId: z.string().uuid().optional(),
  quantityBase: positiveQuantity.optional(),
  destinationLocationId: z.string().uuid().optional(),
  destinationDisposition: z.string().min(1).max(80).optional(),
  expiresAt: z.string().datetime().optional(),
  idempotencyKey,
  reason: reason.optional(),
  confirm: confirmation
});

const formValues = (formData: FormData) => Object.fromEntries(formData.entries());
const errorState = (error: unknown, action?: string): InventoryMutationActionState => error instanceof InventoryMutationError ? {status: error.kind, action} : {status: 'unavailable', action};

export async function createTransferAction(_previous: InventoryMutationActionState, formData: FormData): Promise<InventoryMutationActionState> {
  const parsed = createSchema.safeParse(formValues(formData));
  if (!parsed.success) return {status: 'invalid', action: 'create'};
  const {locale, ...input} = parsed.data;
  const scope = await requireInventoryScope(locale);
  try {
    const transferId = await createTransfer(scope, input);
    revalidatePath(`/${locale}/inventory/transfers`);
    revalidatePath(`/${locale}/inventory`);
    return {status: 'success', action: 'create', transferId};
  } catch (error) { return errorState(error, 'create'); }
}

export async function mutateTransferAction(_previous: InventoryMutationActionState, formData: FormData): Promise<InventoryMutationActionState> {
  const parsed = mutationSchema.safeParse(formValues(formData));
  if (!parsed.success) return {status: 'invalid'};
  const {locale, confirm: _confirm, ...input} = parsed.data;
  const scope = await requireInventoryScope(locale);
  try {
    const transferId = await mutateTransfer(scope, input);
    revalidatePath(`/${locale}/inventory/transfers`);
    revalidatePath(`/${locale}/inventory/transfers/${input.transferId}`);
    revalidatePath(`/${locale}/inventory/balances`);
    return {status: 'success', action: input.action, transferId};
  } catch (error) { return errorState(error, input.action); }
}
