import 'server-only';
import {createClient} from '@supabase/supabase-js';
import {requireServerEnvironment} from './env';

export function createServerSupabaseClient() {
  const environment = requireServerEnvironment();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) throw new Error('NEXT_PUBLIC_SUPABASE_URL must be set on the server before creating a Supabase server client.');
  return createClient(url, environment.SUPABASE_SERVICE_ROLE_KEY, {auth: {persistSession: false, autoRefreshToken: false}});
}
