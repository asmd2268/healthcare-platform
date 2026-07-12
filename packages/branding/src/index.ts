import {platformConfiguration} from '@healthcare/configuration';

export type BrandingSettings = {
  platformName: string;
  organizationNameAr: string;
  organizationNameEn: string;
  branchName?: string;
  logoUrl?: string;
  reportHeader?: string;
  reportFooter?: string;
  showDeveloperAttribution: boolean;
};

export const defaultBranding: BrandingSettings = {
  platformName: 'Healthcare Operations Platform',
  organizationNameAr: 'منشأة تجريبية',
  organizationNameEn: 'Demo Facility',
  branchName: 'Main Branch',
  showDeveloperAttribution: true,
  reportFooter: `${platformConfiguration.developerAttribution.ar} · ${platformConfiguration.developerAttribution.en}`
};
