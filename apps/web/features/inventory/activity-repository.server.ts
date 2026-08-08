import 'server-only';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';
import type {InventoryScope} from './repository';

export type InventoryActivity = {id: string; transferId: string; action: string; createdAt: string};

export async function listRecentInventoryActivity(_scope: InventoryScope, limit = 100): Promise<InventoryActivity[]> {
  const supabase = await createServerUserSupabaseClient();
  const {data, error} = await supabase.from('inventory_transfer_events').select('id,transfer_id,action,created_at').order('created_at', {ascending: false}).limit(Math.min(Math.max(limit, 1), 100));
  if (error) throw new Error('Unable to load inventory activity.');
  return (data ?? []).map((row) => ({id: row.id, transferId: row.transfer_id, action: row.action, createdAt: row.created_at}));
}
