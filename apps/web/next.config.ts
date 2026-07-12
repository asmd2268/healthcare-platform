import type {NextConfig} from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  transpilePackages: ['@healthcare/ui', '@healthcare/auth', '@healthcare/database', '@healthcare/permissions', '@healthcare/localization', '@healthcare/branding', '@healthcare/audit', '@healthcare/workflow', '@healthcare/configuration', '@healthcare/inspections'],
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        {key: 'X-Content-Type-Options', value: 'nosniff'},
        {key: 'X-Frame-Options', value: 'DENY'},
        {key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin'},
        {key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()'},
        {key: 'Content-Security-Policy', value: "default-src 'self'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; object-src 'none'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self' https:; font-src 'self' data: https:; upgrade-insecure-requests"}
      ]
    }];
  }
};

export default createNextIntlPlugin('./i18n/request.ts')(nextConfig);
