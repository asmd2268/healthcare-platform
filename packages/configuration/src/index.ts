export const platformConfiguration = {
  developerAttribution: {ar: 'تطوير: علي أبودهش', en: 'Developed by Ali Abudahash'},
  defaultLocale: 'ar' as const,
  defaultLockTimeoutMinutes: 15
};

export type PlatformConfiguration = typeof platformConfiguration;
