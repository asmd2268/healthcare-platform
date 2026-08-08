import fs from 'node:fs';
import path from 'node:path';
import {describe, expect, it} from 'vitest';

const source = fs.readFileSync(path.join(process.cwd(), 'features/inventory/mutation-repository.server.ts'), 'utf8');

describe('inventory mutation security boundary', () => {
  it('is server-only and uses the signed-in session', () => {
    expect(source).toContain("import 'server-only';");
    expect(source).toContain('createServerUserSupabaseClient');
    expect(source).not.toContain('service_role');
    expect(source).not.toContain('SUPABASE_SERVICE_ROLE');
  });

  it('preflights scope and permission and uses fixed RPC contracts', () => {
    expect(source).toContain("scope_allowed");
    expect(source).toContain('has_platform_permission');
    expect(source).toContain('inventoryRequestHash');
    for (const rpc of ['create_inventory_transfer', 'reserve_inventory_transfer', 'issue_inventory_transfer', 'receive_inventory_transfer', 'reject_inventory_transfer', 'return_rejected_inventory_transfer', 'dispose_rejected_inventory_transfer', 'cancel_inventory_transfer', 'close_inventory_transfer_remainder']) expect(source).toContain(rpc);
  });
});
