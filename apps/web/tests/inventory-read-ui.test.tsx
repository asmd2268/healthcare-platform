import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {NextIntlClientProvider} from 'next-intl';
import {describe, expect, it} from 'vitest';
import {InventoryLocationsView, InventoryTransferDetailView} from '@/components/inventory/read-only-workspace';
import type {InventoryTransferDetail} from '@/features/inventory/repository';

Object.assign(globalThis, {React});

const messages = (locale: 'ar' | 'en') => JSON.parse(fs.readFileSync(path.join(process.cwd(), 'messages', `${locale}.json`), 'utf8'));
const scope = {tenantId: 'tenant-a', organizationId: 'org-a', facilityId: 'facility-a'};
const transfer: InventoryTransferDetail = {
  ...scope, id: '12345678-0000-0000-0000-000000000000', status: 'reserved', sourceLocationId: 'source', sourceCode: 'SRC', sourceNameAr: 'المصدر', sourceNameEn: 'Source', destinationLocationId: 'destination', destinationCode: 'DST', destinationNameAr: 'الوجهة', destinationNameEn: 'Destination', createdAt: '2026-07-28T00:00:00Z', updatedAt: '2026-07-28T00:00:00Z',
  lines: [], allocations: [], reservations: [], operations: [], receiptDestinations: [], events: [], closures: []
};

describe('inventory read-only UI', () => {
  it('renders Arabic inventory content in an RTL-ready localized tree', () => {
    const html = renderToStaticMarkup(<NextIntlClientProvider locale="ar" messages={messages('ar')}><InventoryLocationsView locations={[{...scope, id: 'location', parentLocationId: null, code: 'PHARM', nameAr: 'الصيدلية', nameEn: 'Pharmacy', kind: 'pharmacy', confidential: false, active: true}]} query=""/></NextIntlClientProvider>);
    expect(html).toContain('<h1>مواقع المخزون</h1>');
    expect(html).toContain('الصيدلية');
    expect(html).toContain('للقراءة فقط');
  });

  it('renders a transfer detail with no inventory mutation controls', () => {
    const html = renderToStaticMarkup(<NextIntlClientProvider locale="en" messages={messages('en')}><InventoryTransferDetailView transfer={transfer}/></NextIntlClientProvider>);
    expect(html).toContain('<h1>Transfer 12345678</h1>');
    expect(html).not.toContain('<button');
    expect(html).toContain('exposes no stock or transfer actions');
  });
});
