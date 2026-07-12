import 'server-only';
import {createClient} from '@supabase/supabase-js';
import {hasSupabasePublicConfig, publicEnvironment} from './env';

/** Server user client for future authenticated requests and RLS; never bypasses RLS. */
export function createServerUserSupabaseClient() {
  if (!hasSupabasePublicConfig) throw new Error('Supabase user client is unavailable until NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are configured.');
  return createClient(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL!, publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {auth: {persistSession: false, autoRefreshToken: false}});
}
