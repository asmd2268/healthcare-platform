export type AuthSession = {userId: string; organizationId: string; expiresAt: string; deviceId?: string};
export type AuthProvider = {signIn(input: {email: string; password: string}): Promise<AuthSession>; signOut(): Promise<void>; requestPasswordReset(email: string): Promise<void>};
export type LockSettings = {idleTimeoutMinutes: number; reauthenticationRequiredForSensitiveActions: boolean};
export const defaultLockSettings: LockSettings = {idleTimeoutMinutes: 15, reauthenticationRequiredForSensitiveActions: true};
