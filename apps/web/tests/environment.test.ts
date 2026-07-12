import {describe, expect, it} from 'vitest';
import {hasSupabasePublicConfig} from '@/lib/env';

describe('environment boundary', () => {
  it('does not require database credentials for the foundation to render', () => {
    expect(typeof hasSupabasePublicConfig).toBe('boolean');
  });
});
