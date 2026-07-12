export const permissions = ['platform.view', 'settings.view', 'settings.manage', 'users.view', 'users.manage', 'roles.view', 'roles.manage', 'audit.view', 'branding.manage'] as const;
export type Permission = (typeof permissions)[number];
export type PermissionContext = {permissions: readonly Permission[]};
export const can = (context: PermissionContext, permission: Permission) => context.permissions.includes(permission);
