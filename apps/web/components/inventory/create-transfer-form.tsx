'use client';

import {useActionState, useEffect, useMemo, useState} from 'react';
import {useLocale, useTranslations} from 'next-intl';
import type {InventoryBalance, InventoryLocation} from '@/features/inventory/repository';
import {createTransferAction, type InventoryMutationActionState} from '@/app/[locale]/inventory/transfers/actions';

type AllocationDraft = {balanceId: string; quantity: string};
const initialState: InventoryMutationActionState = {status: 'idle'};
const localName = (locale: string, ar: string | null, en: string, fallback: string) => locale === 'ar' ? (ar || en || fallback) : (en || ar || fallback);

export function CreateTransferForm({locations, balances}: {locations: InventoryLocation[]; balances: InventoryBalance[]}) {
  const t = useTranslations('inventory');
  const locale = useLocale();
  const [state, action, pending] = useActionState(createTransferAction, initialState);
  const [sourceLocationId, setSourceLocationId] = useState('');
  const [destinationLocationId, setDestinationLocationId] = useState('');
  const [allocations, setAllocations] = useState<AllocationDraft[]>([{balanceId: '', quantity: ''}]);
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [idempotencyKey, setIdempotencyKey] = useState('');
  useEffect(() => setIdempotencyKey(globalThis.crypto.randomUUID()), []);

  const usableLocations = locations.filter((location) => location.active && location.kind !== 'transit');
  const sourceBalances = useMemo(() => balances.filter((balance) => balance.locationId === sourceLocationId && balance.disposition === 'available' && balance.batchId), [balances, sourceLocationId]);
  const selectedIds = new Set(allocations.map((allocation) => allocation.balanceId));
  const updateAllocation = (index: number, update: Partial<AllocationDraft>) => setAllocations((current) => current.map((row, rowIndex) => rowIndex === index ? {...row, ...update} : row));
  const serializedAllocations = allocations.map((row) => {
    const balance = sourceBalances.find((candidate) => candidate.id === row.balanceId);
    return balance ? {profileId: balance.profileId, batchId: balance.batchId, channel: balance.recordingChannel, quantityBase: Number(row.quantity)} : null;
  }).filter((row): row is {profileId: string; batchId: string; channel: string; quantityBase: number} => Boolean(row && Number.isFinite(row.quantityBase) && row.quantityBase > 0));
  const locationLabel = (id: string) => { const location = usableLocations.find((candidate) => candidate.id === id); return location ? localName(locale, location.nameAr, location.nameEn, location.code) : t('unavailable'); };

  return <form className="inventory-operation-form" action={action}>
    <input type="hidden" name="locale" value={locale}/><input type="hidden" name="idempotencyKey" value={idempotencyKey}/><input type="hidden" name="allocations" value={JSON.stringify(serializedAllocations)}/>
    <div className="inventory-form-grid">
      <label>{t('source')}<select name="sourceLocationId" value={sourceLocationId} onChange={(event) => {setSourceLocationId(event.target.value); setAllocations([{balanceId: '', quantity: ''}]);}} required><option value="">{t('chooseLocation')}</option>{usableLocations.map((location) => <option key={location.id} value={location.id}>{locationLabel(location.id)}</option>)}</select></label>
      <label>{t('destination')}<select name="destinationLocationId" value={destinationLocationId} onChange={(event) => setDestinationLocationId(event.target.value)} required><option value="">{t('chooseLocation')}</option>{usableLocations.filter((location) => location.id !== sourceLocationId).map((location) => <option key={location.id} value={location.id}>{locationLabel(location.id)}</option>)}</select></label>
    </div>
    <fieldset className="inventory-operation-fieldset"><legend>{t('allocations')}</legend>
      {allocations.map((allocation, index) => <div className="inventory-allocation-row" key={`${index}-${allocation.balanceId}`}>
        <label>{t('item')}<select value={allocation.balanceId} onChange={(event) => updateAllocation(index, {balanceId: event.target.value})} required><option value="">{t('chooseBalance')}</option>{sourceBalances.map((balance) => <option key={balance.id} value={balance.id} disabled={selectedIds.has(balance.id) && balance.id !== allocation.balanceId}>{localName(locale, balance.itemNameAr, balance.itemNameEn, t('unavailable'))} · {balance.lotNumber || t('unknownLot')} · {balance.quantityBase}</option>)}</select></label>
        <label>{t('quantity')}<input className="ui-input" type="number" min="0.000001" step="any" value={allocation.quantity} onChange={(event) => updateAllocation(index, {quantity: event.target.value})} required/></label>
        {allocations.length > 1 ? <button className="ui-button" type="button" onClick={() => setAllocations((current) => current.filter((_, rowIndex) => rowIndex !== index))}>{t('removeAllocation')}</button> : null}
      </div>)}
      <button className="ui-button" type="button" onClick={() => setAllocations((current) => [...current, {balanceId: '', quantity: ''}])}>{t('addAllocation')}</button>
    </fieldset>
    <label>{t('reason')}<textarea className="ui-input" name="reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={3} maxLength={500} required/></label>
    <label className="inventory-confirm"><input type="checkbox" name="confirm" value="true" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} required/>{t('createConfirmation')}</label>
    {state.status !== 'idle' ? <p className={`inventory-action-message ${state.status === 'success' ? 'success' : 'error'}`}>{t(`actionStates.${state.status}`)}</p> : null}
    <button className="ui-button" type="submit" disabled={pending || !idempotencyKey || serializedAllocations.length === 0 || !confirmed}>{pending ? t('saving') : t('createTransfer')}</button>
  </form>;
}
