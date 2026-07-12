import {describe, expect, it} from 'vitest';
import {can, type PermissionContext} from '@healthcare/permissions';

describe('permission utility', () => {
  const context: PermissionContext = {permissions: ['platform.view', 'audit.view']};
  it('allows explicitly granted permissions only', () => {
    expect(can(context, 'audit.view')).toBe(true);
    expect(can(context, 'users.manage')).toBe(false);
  });
});
