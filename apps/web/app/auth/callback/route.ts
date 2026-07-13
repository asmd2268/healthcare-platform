import {NextResponse,type NextRequest} from 'next/server';
import {createServerClient} from '@supabase/ssr';
import {safeLocale} from '@/lib/auth-redirect';

export async function GET(request:NextRequest){
  const url=new URL(request.url);const code=url.searchParams.get('code');const locale=safeLocale(url.searchParams.get('locale'));const next=`/${locale}/settings`;
  const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL;const anonKey=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;if(!code||!supabaseUrl||!anonKey)return NextResponse.redirect(new URL('/ar/login',url));
  const response=NextResponse.redirect(new URL(next,url));const supabase=createServerClient(supabaseUrl,anonKey,{cookies:{getAll:()=>request.cookies.getAll(),setAll:entries=>entries.forEach(({name,value,options})=>response.cookies.set(name,value,options))}});await supabase.auth.exchangeCodeForSession(code);return response;
}
