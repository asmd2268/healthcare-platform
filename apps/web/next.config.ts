import type {NextConfig} from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  transpilePackages: ['@healthcare/ui', '@healthcare/auth', '@healthcare/database', '@healthcare/permissions', '@healthcare/localization', '@healthcare/branding', '@healthcare/audit', '@healthcare/workflow', '@healthcare/configuration'],
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        {key: 'X-Content-Type-Options', value: 'nosniff'},
        {key: 'X-Frame-Options', value: 'DENY'},
        {key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin'},
        {key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()'}
      ]
    }];
  }
};

export default createNextIntlPlugin('./i18n/request.ts')(nextConfig);
