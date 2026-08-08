import Link from 'next/link';
import {useLocale, useTranslations} from 'next-intl';
import {Badge, EmptyState, TableShell} from '@healthcare/ui';
import type {InventoryBalance, InventoryLocation, InventoryTransfer, InventoryTransferDetail} from '@/features/inventory/repository';
import type {Locale} from '@/i18n';

const localName = (locale: Locale, ar: string | null, en: string, fallback: string) => locale === 'ar' ? (ar || en || fallback) : (en || ar || fallback);
const shortId = (id: string) => id.slice(0, 8).toUpperCase();

function InventoryNav() {
  const t = useTranslations('inventory');
  const locale = useLocale();
  return <nav className="inventory-nav" aria-label={t('navLabel')}>
    <Link href={`/${locale}/inventory`}>{t('locations')}</Link>
    <Link href={`/${locale}/inventory/balances`}>{t('balances')}</Link>
    <Link href={`/${locale}/inventory/transfers`}>{t('transfers')}</Link>
  </nav>;
}

function InventoryHeader({title, body}: {title: string; body: string}) {
  const t = useTranslations('inventory');
  return <><InventoryNav/><header className="inventory-heading"><div><p className="eyebrow">{t('eyebrow')}</p><h1>{title}</h1><p>{body}</p></div><Badge>{t('readOnly')}</Badge></header></>;
}

function Empty({children}: {children: React.ReactNode}) {
  return <EmptyState><p>{children}</p></EmptyState>;
}

function FilterForm({children}: {children: React.ReactNode}) {
  const t = useTranslations('inventory');
  return <form className="inventory-filters" method="get">{children}<button className="ui-button" type="submit">{t('applyFilters')}</button><Link className="inventory-reset" href="?">{t('resetFilters')}</Link></form>;
}

export function InventoryLocationsView({locations, query}: {locations: InventoryLocation[]; query: string}) {
  const t = useTranslations('inventory');
  const locale = useLocale() as Locale;
  return <section className="page inventory-page"><InventoryHeader title={t('locations')} body={t('locationsBody')}/><FilterForm><label>{t('search')}<input className="ui-input" name="q" defaultValue={query} placeholder={t('locationSearchPlaceholder')}/></label></FilterForm>{locations.length === 0 ? <Empty>{t('emptyLocations')}</Empty> : <div className="inventory-card-grid">{locations.map((location) => <article className="ui-card inventory-location-card" key={location.id}><div><strong>{localName(locale, location.nameAr, location.nameEn, t('unavailable'))}</strong><p>{location.code}</p></div><div className="inventory-badges"><Badge>{t(`locationKinds.${location.kind}`)}</Badge><Badge>{location.active ? t('active') : t('inactive')}</Badge>{location.confidential ? <Badge>{t('confidential')}</Badge> : null}</div></article>)}</div>}</section>;
}

export function InventoryBalancesView({balances, locations, filters}: {balances: InventoryBalance[]; locations: InventoryLocation[]; filters: {query: string; locationId: string; disposition: string}}) {
  const t = useTranslations('inventory');
  const locale = useLocale() as Locale;
  const number = new Intl.NumberFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {maximumFractionDigits: 6});
  const date = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {dateStyle: 'medium'});
  const dispositions = ['available','reserved','quarantine','damaged','expired','returns_hold','wastage_hold','transit'];
  return <section className="page inventory-page"><InventoryHeader title={t('balances')} body={t('balancesBody')}/><FilterForm>
    <label>{t('search')}<input className="ui-input" name="q" defaultValue={filters.query} placeholder={t('balanceSearchPlaceholder')}/></label>
    <label>{t('location')}<select name="location" defaultValue={filters.locationId}><option value="">{t('allLocations')}</option>{locations.map((location) => <option key={location.id} value={location.id}>{localName(locale, location.nameAr, location.nameEn, location.code)}</option>)}</select></label>
    <label>{t('disposition')}<select name="disposition" defaultValue={filters.disposition}><option value="">{t('allDispositions')}</option>{dispositions.map((value) => <option key={value} value={value}>{t(`dispositions.${value}`)}</option>)}</select></label>
  </FilterForm>{balances.length === 0 ? <Empty>{t('emptyBalances')}</Empty> : <TableShell><div className="inventory-table-wrap"><table><thead><tr><th>{t('item')}</th><th>{t('location')}</th><th>{t('lot')}</th><th>{t('expiry')}</th><th>{t('disposition')}</th><th>{t('quantity')}</th><th>{t('channel')}</th></tr></thead><tbody>{balances.map((balance) => <tr key={balance.id}><td>{localName(locale, balance.itemNameAr, balance.itemNameEn, t('unavailable'))}</td><td><strong>{localName(locale, balance.locationNameAr, balance.locationNameEn, balance.locationCode)}</strong><small>{balance.locationCode}</small></td><td>{balance.lotNumber || t(`lotStatuses.${balance.lotStatus}`)}</td><td>{balance.expiryDate ? date.format(new Date(`${balance.expiryDate}T00:00:00Z`)) : t(`expiryStatuses.${balance.expiryStatus}`)}</td><td><Badge>{t(`dispositions.${balance.disposition}`)}</Badge></td><td>{number.format(balance.quantityBase)} <small>{localName(locale, balance.baseUnitAr, balance.baseUnitEn ?? '', '')}</small></td><td>{t(`channels.${balance.recordingChannel}`)}</td></tr>)}</tbody></table></div></TableShell>}</section>;
}

export function InventoryTransfersView({transfers, filters}: {transfers: InventoryTransfer[]; filters: {query: string; status: string}}) {
  const t = useTranslations('inventory');
  const locale = useLocale() as Locale;
  const date = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {dateStyle: 'medium', timeStyle: 'short'});
  const statuses = ['draft','reserved','partially_issued','issued','receiving','completed','cancelled'];
  return <section className="page inventory-page"><InventoryHeader title={t('transfers')} body={t('transfersBody')}/><FilterForm>
    <label>{t('search')}<input className="ui-input" name="q" defaultValue={filters.query} placeholder={t('transferSearchPlaceholder')}/></label>
    <label>{t('status')}<select name="status" defaultValue={filters.status}><option value="">{t('allStatuses')}</option>{statuses.map((value) => <option key={value} value={value}>{t(`statuses.${value}`)}</option>)}</select></label>
  </FilterForm>{transfers.length === 0 ? <Empty>{t('emptyTransfers')}</Empty> : <TableShell><div className="inventory-table-wrap"><table><thead><tr><th>{t('transfer')}</th><th>{t('status')}</th><th>{t('source')}</th><th>{t('destination')}</th><th>{t('updated')}</th></tr></thead><tbody>{transfers.map((transfer) => <tr key={transfer.id}><td><Link href={`/${locale}/inventory/transfers/${transfer.id}`}>{t('transferReference', {id: shortId(transfer.id)})}</Link></td><td><Badge>{t(`statuses.${transfer.status}`)}</Badge></td><td>{localName(locale, transfer.sourceNameAr, transfer.sourceNameEn, t('restrictedLocation'))}</td><td>{localName(locale, transfer.destinationNameAr, transfer.destinationNameEn, t('restrictedLocation'))}</td><td>{date.format(new Date(transfer.updatedAt))}</td></tr>)}</tbody></table></div></TableShell>}</section>;
}

export function InventoryTransferDetailView({transfer}: {transfer: InventoryTransferDetail}) {
  const t = useTranslations('inventory');
  const locale = useLocale() as Locale;
  const number = new Intl.NumberFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {maximumFractionDigits: 6});
  const date = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-US', {dateStyle: 'medium', timeStyle: 'short'});
  return <section className="page inventory-page"><InventoryNav/><Link className="inventory-back" href={`/${locale}/inventory/transfers`}>{t('backToTransfers')}</Link><header className="inventory-heading"><div><p className="eyebrow">{t('transfer')}</p><h1>{t('transferReference', {id: shortId(transfer.id)})}</h1><p>{localName(locale, transfer.sourceNameAr, transfer.sourceNameEn, t('restrictedLocation'))} → {localName(locale, transfer.destinationNameAr, transfer.destinationNameEn, t('restrictedLocation'))}</p></div><Badge>{t(`statuses.${transfer.status}`)}</Badge></header><p className="inventory-readonly-note">{t('detailReadOnlyNotice')}</p>
    <div className="inventory-detail-grid"><article className="ui-card"><h2>{t('linesAndAllocations')}</h2>{transfer.lines.length === 0 ? <p>{t('emptyLines')}</p> : transfer.lines.map((line) => <div className="inventory-detail-record" key={line.id}><strong>{localName(locale, line.itemNameAr, line.itemNameEn, t('unavailable'))}</strong><span>{t('requested')}: {number.format(line.requestedQuantityBase)}</span>{transfer.allocations.filter((allocation) => allocation.lineId === line.id).map((allocation) => <small key={allocation.id}>{t('allocationSummary', {location: allocation.sourceCode || t('restrictedLocation'), lot: allocation.lotNumber || t('unknownLot'), quantity: number.format(allocation.plannedQuantityBase)})}</small>)}</div>)}</article>
      <article className="ui-card"><h2>{t('reservations')}</h2>{transfer.reservations.length === 0 ? <p>{t('emptyReservations')}</p> : transfer.reservations.map((reservation) => <div className="inventory-detail-record" key={reservation.id}><strong>{t('remaining')}: {number.format(reservation.remainingQuantityBase)}</strong><span>{t('reservedQuantity')}: {number.format(reservation.quantityBase)}</span><span>{t('adjustedQuantity')}: {number.format(reservation.adjustedQuantityBase)}</span><small>{t('expiresAt')}: {date.format(new Date(reservation.expiresAt))}</small></div>)}</article>
      <article className="ui-card"><h2>{t('operations')}</h2>{transfer.operations.length === 0 ? <p>{t('emptyOperations')}</p> : transfer.operations.map((operation) => <div className="inventory-detail-record" key={operation.id}><strong>{t(`operationTypes.${operation.type}`)}</strong><span>{operation.quantityBase === null ? t('notApplicable') : number.format(operation.quantityBase)}</span><small>{operation.destinationLocationId ? localName(locale, operation.destinationNameAr, operation.destinationNameEn ?? '', operation.destinationCode || t('restrictedLocation')) : t('notApplicable')} · {date.format(new Date(operation.createdAt))}</small></div>)}</article>
      <article className="ui-card"><h2>{t('receiptDestinations')}</h2>{transfer.receiptDestinations.length === 0 ? <p>{t('emptyReceiptDestinations')}</p> : transfer.receiptDestinations.map((receipt) => <div className="inventory-detail-record" key={receipt.id}><strong>{localName(locale, receipt.destinationNameAr, receipt.destinationNameEn ?? '', receipt.destinationCode || t('restrictedLocation'))}</strong><span>{number.format(receipt.quantityBase)}</span><small>{date.format(new Date(receipt.createdAt))}</small></div>)}</article>
      <article className="ui-card"><h2>{t('remainderClosures')}</h2>{transfer.closures.length === 0 ? <p>{t('emptyClosures')}</p> : transfer.closures.map((closure) => <div className="inventory-detail-record" key={closure.id}><strong>{number.format(closure.quantityBase)}</strong><span>{closure.reason}</span><small>{date.format(new Date(closure.createdAt))}</small></div>)}</article>
      <article className="ui-card"><h2>{t('events')}</h2>{transfer.events.length === 0 ? <p>{t('emptyEvents')}</p> : transfer.events.map((event) => <div className="inventory-detail-record" key={event.id}><strong>{event.action}</strong><small>{date.format(new Date(event.createdAt))}</small></div>)}</article>
    </div>
  </section>;
}
