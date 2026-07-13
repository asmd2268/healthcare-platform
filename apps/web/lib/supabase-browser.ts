'use client';
import {createBrowserClient} from '@supabase/ssr';
import {publicEnvironment, hasSupabasePublicConfig} from './env';

/** Browser client for Supabase Auth only; database authorization remains enforced by RLS. */
export function createBrowserSupabaseClient() {
  if (!hasSupabasePublicConfig) return null;
  return createBrowserClient(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL!,publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
}
