import {platformConfiguration} from '@healthcare/configuration';

export type BrandingSettings = {
  platformNameAr: string;
  platformNameEn: string;
  organizationNameAr: string;
  organizationNameEn: string;
  facilityNameAr?: string;
  facilityNameEn?: string;
  branchNameAr?: string;
  branchNameEn?: string;
  logoUrl?: string;
  faviconUrl?: string;
  primaryColor: string;
  accentColor: string;
  contactEmail?: string;
  reportHeaderAr?: string;
  reportHeaderEn?: string;
  reportFooterAr?: string;
  reportFooterEn?: string;
  emailSenderNameAr?: string;
  emailSenderNameEn?: string;
  showDeveloperAttribution: boolean;
};

export const defaultBranding: BrandingSettings = {
  platformNameAr: 'منصة عمليات الرعاية الصحية',
  platformNameEn: 'Healthcare Operations Platform',
  organizationNameAr: 'منشأة تجريبية',
  organizationNameEn: 'Demo Facility',
  facilityNameAr: 'المنشأة الرئيسية',
  facilityNameEn: 'Main Facility',
  branchNameAr: 'الفرع الرئيسي',
  branchNameEn: 'Main Branch',
  primaryColor: '#0f766e',
  accentColor: '#0d9488',
  showDeveloperAttribution: true,
  reportFooterAr: platformConfiguration.developerAttribution.ar,
  reportFooterEn: platformConfiguration.developerAttribution.en,
  emailSenderNameAr: 'منصة عمليات الرعاية الصحية',
  emailSenderNameEn: 'Healthcare Operations Platform'
};

const stringKeys = [
  'platformNameAr','platformNameEn','organizationNameAr','organizationNameEn',
  'facilityNameAr','facilityNameEn','branchNameAr','branchNameEn','logoUrl',
  'faviconUrl','contactEmail','reportHeaderAr','reportHeaderEn','reportFooterAr',
  'reportFooterEn','emailSenderNameAr','emailSenderNameEn'
] as const;

export function mergeBranding(...layers: Array<Partial<BrandingSettings> | null | undefined>): BrandingSettings {
  const merged: BrandingSettings = {...defaultBranding};
  for (const layer of layers) {
    if (!layer) continue;
    for (const key of stringKeys) {
      const value = layer[key];
      if (typeof value === 'string' && value.trim()) merged[key] = value.trim();
    }
    if (typeof layer.primaryColor === 'string' && /^#[0-9a-f]{6}$/i.test(layer.primaryColor)) merged.primaryColor = layer.primaryColor;
    if (typeof layer.accentColor === 'string' && /^#[0-9a-f]{6}$/i.test(layer.accentColor)) merged.accentColor = layer.accentColor;
    if (typeof layer.showDeveloperAttribution === 'boolean') merged.showDeveloperAttribution = layer.showDeveloperAttribution;
  }
  return merged;
}

export function localizedBranding(branding: BrandingSettings, locale: 'ar' | 'en') {
  const arabic = locale === 'ar';
  return {
    platformName: arabic ? branding.platformNameAr : branding.platformNameEn,
    organizationName: arabic ? branding.organizationNameAr : branding.organizationNameEn,
    facilityName: arabic ? branding.facilityNameAr : branding.facilityNameEn,
    branchName: arabic ? branding.branchNameAr : branding.branchNameEn,
    reportHeader: arabic ? branding.reportHeaderAr : branding.reportHeaderEn,
    reportFooter: arabic ? branding.reportFooterAr : branding.reportFooterEn,
    emailSenderName: arabic ? branding.emailSenderNameAr : branding.emailSenderNameEn
  };
}
