import createMiddleware from 'next-intl/middleware';
import {NextResponse, type NextRequest} from 'next/server';
import {defaultLocale, locales} from './i18n';

const intlMiddleware = createMiddleware({locales, defaultLocale, localePrefix: 'always'});
const protectedSegments = new Set(['settings', 'profile', 'audit']);

export default function middleware(request: NextRequest) {
  const response = intlMiddleware(request);
  const [, locale, segment] = request.nextUrl.pathname.split('/');
  if (locales.includes(locale as (typeof locales)[number]) && protectedSegments.has(segment) && !request.cookies.get('platform-session')) {
    return NextResponse.redirect(new URL(`/${locale}/login`, request.url));
  }
  return response;
}

export const config = {matcher: ['/', '/(ar|en)/:path*']};
