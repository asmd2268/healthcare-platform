import 'server-only';
import {z} from 'zod';
import {mergeBranding, type BrandingSettings} from '@healthcare/branding';
import {resolveDeploymentModules, type DeploymentProfile, type LicenseEnforcement} from '@healthcare/licensing';

const optionalString = z.preprocess((value) => value === '' ? undefined : value, z.string().optional());
const optionalBoolean = z.preprocess((value) => {
  if (value === '' || value === undefined) return undefined;
  if (value === 'true') return true;
  if (value === 'false') return false;
  return value;
}, z.boolean().optional());

const schema = z.object({
  PLATFORM_DEPLOYMENT_PROFILE: z.enum(['full','inventory','quality','medication-safety','custom']).default('full'),
  PLATFORM_DEPLOYMENT_MODULES: optionalString,
  PLATFORM_LICENSE_ENFORCEMENT: z.enum(['disabled','strict']).default('disabled'),
  PLATFORM_BRAND_NAME_AR: optionalString,
  PLATFORM_BRAND_NAME_EN: optionalString,
  PLATFORM_ORGANIZATION_NAME_AR: optionalString,
  PLATFORM_ORGANIZATION_NAME_EN: optionalString,
  PLATFORM_FACILITY_NAME_AR: optionalString,
  PLATFORM_FACILITY_NAME_EN: optionalString,
  PLATFORM_LOGO_URL: optionalString.pipe(z.string().url().startsWith('https://').optional()),
  PLATFORM_FAVICON_URL: optionalString.pipe(z.string().url().startsWith('https://').optional()),
  PLATFORM_PRIMARY_COLOR: optionalString.pipe(z.string().regex(/^#[0-9a-f]{6}$/i).optional()),
  PLATFORM_ACCENT_COLOR: optionalString.pipe(z.string().regex(/^#[0-9a-f]{6}$/i).optional()),
  PLATFORM_CONTACT_EMAIL: optionalString.pipe(z.string().email().optional()),
  PLATFORM_REPORT_FOOTER_AR: optionalString,
  PLATFORM_REPORT_FOOTER_EN: optionalString,
  PLATFORM_SHOW_DEVELOPER_ATTRIBUTION: optionalBoolean
});

const environment = schema.parse({
  PLATFORM_DEPLOYMENT_PROFILE: process.env.PLATFORM_DEPLOYMENT_PROFILE,
  PLATFORM_DEPLOYMENT_MODULES: process.env.PLATFORM_DEPLOYMENT_MODULES,
  PLATFORM_LICENSE_ENFORCEMENT: process.env.PLATFORM_LICENSE_ENFORCEMENT,
  PLATFORM_BRAND_NAME_AR: process.env.PLATFORM_BRAND_NAME_AR,
  PLATFORM_BRAND_NAME_EN: process.env.PLATFORM_BRAND_NAME_EN,
  PLATFORM_ORGANIZATION_NAME_AR: process.env.PLATFORM_ORGANIZATION_NAME_AR,
  PLATFORM_ORGANIZATION_NAME_EN: process.env.PLATFORM_ORGANIZATION_NAME_EN,
  PLATFORM_FACILITY_NAME_AR: process.env.PLATFORM_FACILITY_NAME_AR,
  PLATFORM_FACILITY_NAME_EN: process.env.PLATFORM_FACILITY_NAME_EN,
  PLATFORM_LOGO_URL: process.env.PLATFORM_LOGO_URL,
  PLATFORM_FAVICON_URL: process.env.PLATFORM_FAVICON_URL,
  PLATFORM_PRIMARY_COLOR: process.env.PLATFORM_PRIMARY_COLOR,
  PLATFORM_ACCENT_COLOR: process.env.PLATFORM_ACCENT_COLOR,
  PLATFORM_CONTACT_EMAIL: process.env.PLATFORM_CONTACT_EMAIL,
  PLATFORM_REPORT_FOOTER_AR: process.env.PLATFORM_REPORT_FOOTER_AR,
  PLATFORM_REPORT_FOOTER_EN: process.env.PLATFORM_REPORT_FOOTER_EN,
  PLATFORM_SHOW_DEVELOPER_ATTRIBUTION: process.env.PLATFORM_SHOW_DEVELOPER_ATTRIBUTION
});

const environmentBranding: Partial<BrandingSettings> = {
  platformNameAr: environment.PLATFORM_BRAND_NAME_AR,
  platformNameEn: environment.PLATFORM_BRAND_NAME_EN,
  organizationNameAr: environment.PLATFORM_ORGANIZATION_NAME_AR,
  organizationNameEn: environment.PLATFORM_ORGANIZATION_NAME_EN,
  facilityNameAr: environment.PLATFORM_FACILITY_NAME_AR,
  facilityNameEn: environment.PLATFORM_FACILITY_NAME_EN,
  logoUrl: environment.PLATFORM_LOGO_URL,
  faviconUrl: environment.PLATFORM_FAVICON_URL,
  primaryColor: environment.PLATFORM_PRIMARY_COLOR,
  accentColor: environment.PLATFORM_ACCENT_COLOR,
  contactEmail: environment.PLATFORM_CONTACT_EMAIL,
  reportFooterAr: environment.PLATFORM_REPORT_FOOTER_AR,
  reportFooterEn: environment.PLATFORM_REPORT_FOOTER_EN,
  showDeveloperAttribution: environment.PLATFORM_SHOW_DEVELOPER_ATTRIBUTION
};

export const commercialConfiguration = {
  deploymentProfile: environment.PLATFORM_DEPLOYMENT_PROFILE as DeploymentProfile,
  deploymentModules: resolveDeploymentModules(environment.PLATFORM_DEPLOYMENT_PROFILE, environment.PLATFORM_DEPLOYMENT_MODULES),
  licenseEnforcement: environment.PLATFORM_LICENSE_ENFORCEMENT as LicenseEnforcement,
  branding: mergeBranding(environmentBranding)
};
