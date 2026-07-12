import createMiddleware from 'next-intl/middleware';
import {NextResponse, type NextRequest} from 'next/server';
import {defaultLocale, locales} from './i18n';

const intlMiddleware = createMiddleware({locales, defaultLocale, localePrefix: 'always'});
const protectedSegments = new Set(['settings', 'profile', 'audit']);

export default function middleware(request: NextRequest) {
  const response = intlMiddleware(request);
  const [, locale, segment] = request.nextUrl.pathname.split('/');
  if (locales.includes(locale as (typeof locales)[number]) && protectedSegments.has(segment)) {
    // Authentication is intentionally unimplemented. Never infer authentication
    // from arbitrary client-controlled cookie presence. Production fails closed;
    // development exposes only clearly labelled placeholder screens.
    if (process.env.NODE_ENV === 'production') return NextResponse.redirect(new URL(`/${locale}/login`, request.url));
    response.headers.set('X-Platform-Auth-Mode', 'development-placeholder');
  }
  return response;
}

export const config = {matcher: ['/', '/(ar|en)/:path*']};
