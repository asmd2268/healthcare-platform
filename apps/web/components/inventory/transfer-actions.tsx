'use client';

import {useActionState, useEffect, useMemo, useState} from 'react';
import {useLocale, useTranslations} from 'next-intl';
import type {InventoryLocation, InventoryTransferDetail} from '@/features/inventory/repository';
import {deriveAllocationProgress, type TransferCapabilities, type TransferMutationAction} from '@/features/inventory/mutations';
import {mutateTransferAction, type InventoryMutationActionState} from '@/app/[locale]/inventory/transfers/actions';

type Progress = ReturnType<typeof deriveAllocationProgress>[number];
const initialState: InventoryMutationActionState = {status: 'idle'};
const localName = (locale: string, ar: string | null, en: string, fallback: string) => locale === 'ar' ? (ar || en || fallback) : (en || ar || fallback);
const localDateTime = (value: Date) => { const pad = (part: number) => String(part).padStart(2, '0'); return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}T${pad(value.getHours())}:${pad(value.getMinutes())}`; };
const descendant = (locations: InventoryLocation[], rootId: string, candidateId: string) => { let current = locations.find((location) => location.id === candidateId); while (current) { if (current.id === rootId) return true; current = current.parentLocationId ? locations.find((location) => location.id === current?.parentLocationId) : undefined; } return false; };

function TransferActionForm({actionName, transfer, progress, locations, maxQuantity}: {actionName: TransferMutationAction; transfer: InventoryTransferDetail; progress?: Progress; locations: InventoryLocation[]; maxQuantity?: number}) {
  const t = useTranslations('inventory');
  const locale = useLocale();
  const [state, action, pending] = useActionState(mutateTransferAction, initialState);
  const [idempotencyKey, setIdempotencyKey] = useState('');
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [destinationLocationId, setDestinationLocationId] = useState('');
  const [destinationDisposition, setDestinationDisposition] = useState(actionName === 'dispose' ? 'quarantine' : 'available');
  const [expiresAtLocal, setExpiresAtLocal] = useState('');
  useEffect(() => { setIdempotencyKey(globalThis.crypto.randomUUID()); if (actionName === 'reserve') setExpiresAtLocal(localDateTime(new Date(Date.now() + 86_400_000))); }, [actionName]);
  const destinationOptions = useMemo(() => locations.filter((location) => location.active && descendant(locations, transfer.destinationLocationId, location.id)), [locations, transfer.destinationLocationId]);
  const expiresAt = expiresAtLocal ? new Date(expiresAtLocal).toISOString() : '';
  const needsQuantity = !['reserve', 'cancel'].includes(actionName);
  const needsReason = actionName !== 'reserve';
  const needsConfirmation = actionName !== 'reserve';
  const valid = idempotencyKey && (!needsQuantity || Boolean(progress?.allocationId && (maxQuantity ?? 0) > 0)) && (!needsReason || reason.trim().length >= 3) && (!needsConfirmation || confirmed) && (actionName !== 'receive' || Boolean(destinationLocationId)) && (actionName !== 'reserve' || Boolean(expiresAt));
  const inputName = actionName === 'issue' ? 'issue' : actionName === 'receive' ? 'receive' : actionName === 'reject' ? 'reject' : actionName === 'return' ? 'return' : actionName === 'dispose' ? 'dispose' : actionName === 'close_remainder' ? 'close_remainder' : actionName;
  return <article className="inventory-action-card"><h3>{t(`actions.${inputName}`)}</h3><p>{t(`actionDescriptions.${inputName}`)}</p><form action={action}>
    <input type="hidden" name="locale" value={locale}/><input type="hidden" name="action" value={actionName}/><input type="hidden" name="transferId" value={transfer.id}/><input type="hidden" name="idempotencyKey" value={idempotencyKey}/><input type="hidden" name="allocationId" value={progress?.allocationId ?? ''}/><input type="hidden" name="lineId" value={progress?.lineId ?? ''}/><input type="hidden" name="profileId" value={progress?.profileId ?? ''}/><input type="hidden" name="expiresAt" value={expiresAt}/>
    {needsQuantity ? <label>{t('quantity')}<input className="ui-input" name="quantityBase" type="number" min="0.000001" max={maxQuantity} step="any" required/></label> : null}
    {actionName === 'receive' ? <label>{t('destination')}<select className="ui-input" name="destinationLocationId" value={destinationLocationId} onChange={(event) => setDestinationLocationId(event.target.value)} required><option value="">{t('chooseLocation')}</option>{destinationOptions.map((location) => <option key={location.id} value={location.id}>{localName(locale, location.nameAr, location.nameEn, location.code)}</option>)}</select></label> : null}
    {actionName === 'receive' || actionName === 'dispose' ? <label>{t('disposition')}<select className="ui-input" name="destinationDisposition" value={destinationDisposition} onChange={(event) => setDestinationDisposition(event.target.value)}>{['available','quarantine','damaged','expired','wastage_hold'].filter((value) => actionName === 'receive' || value !== 'available').map((value) => <option key={value} value={value}>{t(`dispositions.${value}`)}</option>)}</select></label> : null}
    {actionName === 'reserve' ? <label>{t('reservationExpiry')}<input className="ui-input" type="datetime-local" value={expiresAtLocal} onChange={(event) => setExpiresAtLocal(event.target.value)} required/></label> : null}
    {needsReason ? <label>{t('reason')}<textarea className="ui-input" name="reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={3} maxLength={500} required/></label> : null}
    {needsConfirmation ? <label className="inventory-confirm"><input type="checkbox" name="confirm" value="true" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} required/>{t('actionConfirmation')}</label> : <input type="hidden" name="confirm" value="true"/>}
    {state.status !== 'idle' ? <p className={`inventory-action-message ${state.status === 'success' ? 'success' : 'error'}`}>{t(`actionStates.${state.status}`)}</p> : null}
    <button className="ui-button" type="submit" disabled={pending || !valid}>{pending ? t('saving') : t('actions.submit')}</button>
  </form></article>;
}

export function TransferActions({transfer, locations, capabilities}: {transfer: InventoryTransferDetail; locations: InventoryLocation[]; capabilities: TransferCapabilities}) {
  const t = useTranslations('inventory');
  const progress = deriveAllocationProgress(transfer);
  const show = (action: keyof TransferCapabilities) => capabilities[action];
  return <section className="inventory-operations"><div className="inventory-operation-heading"><h2>{t('operationsPanel')}</h2><p>{t('operationsPanelBody')}</p></div>
    {show('reserve') && transfer.status === 'draft' ? <TransferActionForm actionName="reserve" transfer={transfer} locations={locations}/> : null}
    {show('cancel') && ['draft','reserved'].includes(transfer.status) ? <TransferActionForm actionName="cancel" transfer={transfer} locations={locations}/> : null}
    {(['issue','receive','reject','return','dispose','close_remainder'] as TransferMutationAction[]).flatMap((action) => {
      if (!show(action)) return [];
      return progress.filter((item) => (action === 'issue' || action === 'close_remainder') ? item.issueRemaining > 0 : action === 'receive' || action === 'reject' ? item.transitRemaining > 0 : item.rejectedRemaining > 0).map((item) => {
        const max = action === 'issue' || action === 'close_remainder' ? item.issueRemaining : action === 'receive' || action === 'reject' ? item.transitRemaining : item.rejectedRemaining;
        return <TransferActionForm key={`${action}-${item.allocationId}`} actionName={action} transfer={transfer} progress={item} locations={locations} maxQuantity={max}/>;
      });
    })}
    {!show('reserve') && !show('cancel') && !(['issue','receive','reject','return','dispose','close_remainder'] as TransferMutationAction[]).some((action) => show(action)) ? <p className="inventory-readonly-note">{t('noOperationPermission')}</p> : null}
    {show('issue') || show('receive') || show('reject') || show('return') || show('dispose') || show('close_remainder') ? <p className="inventory-operation-footnote">{t('operationsServerEnforced')}</p> : null}
  </section>;
}
