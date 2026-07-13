import 'server-only';
import {createServerClient} from '@supabase/ssr';
import {cookies} from 'next/headers';
import {hasSupabasePublicConfig, publicEnvironment} from './env';

/** Authenticated request client. It always uses the anon key and is subject to RLS. */
export async function createServerUserSupabaseClient() {
  if (!hasSupabasePublicConfig) throw new Error('Supabase authentication is unavailable because public Supabase configuration is missing.');
  const cookieStore=await cookies();
  return createServerClient(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL!,publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{
    cookies:{getAll:()=>cookieStore.getAll(),setAll:entries=>{try{entries.forEach(({name,value,options})=>cookieStore.set(name,value,options));}catch{/* Server Components cannot set cookies. Route handlers and middleware refresh them. */}}}
  });
}
