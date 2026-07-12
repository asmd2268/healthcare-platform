import createMiddleware from 'next-intl/middleware';
import {createServerClient} from '@supabase/ssr';
import {NextResponse,type NextRequest} from 'next/server';
import {defaultLocale,locales} from './i18n';
import {authenticationRequired,protectedRouteSegments} from './lib/auth-policy';

const intlMiddleware=createMiddleware({locales,defaultLocale,localePrefix:'always'});

export default async function middleware(request:NextRequest){
  const response=intlMiddleware(request); const [,locale,segment]=request.nextUrl.pathname.split('/');
  if(!locales.includes(locale as (typeof locales)[number])||!protectedRouteSegments.has(segment))return response;
  const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL; const anonKey=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(authenticationRequired(Boolean(supabaseUrl&&anonKey),false)||!supabaseUrl||!anonKey){const denied=NextResponse.redirect(new URL(`/${locale}/login`,request.url));denied.headers.set('X-Platform-Auth-Mode','unavailable-fail-closed');return denied;}
  const supabase=createServerClient(supabaseUrl,anonKey,{cookies:{getAll:()=>request.cookies.getAll(),setAll:entries=>entries.forEach(({name,value,options})=>response.cookies.set(name,value,options))}});
  const {data:{user}}=await supabase.auth.getUser();
  if(authenticationRequired(true,Boolean(user))){const denied=NextResponse.redirect(new URL(`/${locale}/login`,request.url));response.cookies.getAll().forEach(cookie=>denied.cookies.set(cookie));denied.headers.set('X-Platform-Auth-Mode','authenticated-required');return denied;}
  return response;
}
export const config={matcher:['/','/(ar|en)/:path*']};
