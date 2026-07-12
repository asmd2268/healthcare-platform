import 'server-only';
import {createClient} from '@supabase/supabase-js';
import {publicEnvironment, requireAdminEnvironment} from './env';

/**
 * Admin-only client. It bypasses RLS and must never be used for normal user
 * requests, rendering, or client code. Invoke only from reviewed server jobs.
 */
export function createAdminSupabaseClient() {
  const admin = requireAdminEnvironment();
  if (!publicEnvironment.NEXT_PUBLIC_SUPABASE_URL) throw new Error('NEXT_PUBLIC_SUPABASE_URL is required before an admin client can be created.');
  return createClient(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL, admin.SUPABASE_SERVICE_ROLE_KEY, {auth: {persistSession: false, autoRefreshToken: false}});
}
