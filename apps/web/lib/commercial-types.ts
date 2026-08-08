import type {BrandingSettings} from '@healthcare/branding';
import type {CommercialSummary,DeploymentProfile,LicenseEnforcement,ModuleKey} from '@healthcare/licensing';

export type CommercialScope = {tenantId:string;organizationId:string|null;facilityId:string|null};
export type PlatformExperience = {
  branding: BrandingSettings;
  enabledModules: ModuleKey[];
  deploymentProfile: DeploymentProfile;
  licenseEnforcement: LicenseEnforcement;
  commercialSummary: CommercialSummary | null;
  scope: CommercialScope | null;
};
