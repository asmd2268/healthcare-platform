import fs from 'node:fs';
import path from 'node:path';
import {describe, expect, it} from 'vitest';

const source = fs.readFileSync(path.join(process.cwd(), 'features/inventory/activity-repository.server.ts'), 'utf8');

describe('inventory activity security boundary', () => {
  it('uses server-only signed-in Supabase access and bounded reads', () => {
    expect(source).toContain("import 'server-only';");
    expect(source).toContain('createServerUserSupabaseClient');
    expect(source).toContain("from('inventory_transfer_events')");
    expect(source).toContain('Math.min(Math.max(limit, 1), 100)');
    expect(source).not.toContain('service_role');
    expect(source).not.toContain('insert(');
    expect(source).not.toContain('update(');
    expect(source).not.toContain('delete(');
  });
});
