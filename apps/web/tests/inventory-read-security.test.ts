import fs from 'node:fs';
import path from 'node:path';
import {describe, expect, it} from 'vitest';

const source = fs.readFileSync(path.join(process.cwd(), 'features/inventory/supabase-repository.server.ts'), 'utf8');

describe('inventory server read boundary', () => {
  it('uses the signed-in user client and never imports an admin or service-role client', () => {
    expect(source).toContain('createServerUserSupabaseClient');
    expect(source).not.toContain('supabase-admin');
    expect(source).not.toContain('SUPABASE_SERVICE_ROLE_KEY');
  });

  it('scopes every root list and detail query to tenant, organization, and facility', () => {
    expect(source.match(/\.eq\('tenant_id', scope\.tenantId\)/g)?.length).toBeGreaterThanOrEqual(4);
    expect(source.match(/\.eq\('organization_id', scope\.organizationId\)/g)?.length).toBeGreaterThanOrEqual(4);
    expect(source.match(/\.eq\('facility_id', scope\.facilityId\)/g)?.length).toBeGreaterThanOrEqual(4);
  });

  it('does not select transfer event metadata or actor identity', () => {
    const eventSelect = source.match(/from\('inventory_transfer_events'\)\.select\('([^']+)'\)/)?.[1] ?? '';
    expect(eventSelect).not.toContain('metadata');
    expect(eventSelect).not.toContain('actor_id');
  });
});
