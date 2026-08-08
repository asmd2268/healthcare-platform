export const moduleKeys = [
  'core','inventory','inspections','medication_errors','policies','capa',
  'reporting','administration','audit'
] as const;

export type ModuleKey = (typeof moduleKeys)[number];
export type DeploymentProfile = 'full' | 'inventory' | 'quality' | 'medication-safety' | 'custom';
export type LicenseEnforcement = 'disabled' | 'strict';

export const deploymentProfiles: Record<Exclude<DeploymentProfile,'custom'>, readonly ModuleKey[]> = {
  full: moduleKeys,
  inventory: ['core','inventory','audit'],
  quality: ['core','inspections','policies','capa','reporting','audit'],
  'medication-safety': ['core','medication_errors','capa','reporting','audit']
};

export const isModuleKey = (value: string): value is ModuleKey => moduleKeys.includes(value as ModuleKey);

export function resolveDeploymentModules(profile: DeploymentProfile, customModules = ''): ModuleKey[] {
  if (profile !== 'custom') return [...deploymentProfiles[profile]];
  const selected = customModules.split(',').map((value) => value.trim()).filter(isModuleKey);
  return [...new Set<ModuleKey>(['core',...selected])];
}

export function intersectModuleAccess(deployment: readonly ModuleKey[], licensed: readonly ModuleKey[], enforcement: LicenseEnforcement): ModuleKey[] {
  if (enforcement === 'disabled') return [...deployment];
  const licensedSet = new Set<ModuleKey>(['core',...licensed]);
  return deployment.filter((module) => licensedSet.has(module));
}

export type CommercialSummary = {
  licenseModel: 'monthly' | 'annual' | 'perpetual' | 'enterprise' | 'trial';
  status: 'trial' | 'active';
  hostingMode: 'cloud' | 'on_premises' | 'private_cloud';
  startsAt: string;
  expiresAt: string | null;
  graceEndsAt: string | null;
  whiteLabelEnabled: boolean;
  maxUsers: number | null;
  maxFacilities: number | null;
  modules: ModuleKey[];
};
