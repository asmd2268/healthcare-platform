'use client';

import {createClient} from '@supabase/supabase-js';
import {publicEnvironment, hasSupabasePublicConfig} from './env';

export function createBrowserSupabaseClient() {
  if (!hasSupabasePublicConfig) return null;
  return createClient(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL!, publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
}
