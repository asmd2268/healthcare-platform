import fs from 'node:fs';
import path from 'node:path';
import {describe, expect, it} from 'vitest';

function keys(value: unknown, prefix = ''): string[] {
  if (typeof value !== 'object' || value === null) return [prefix];
  return Object.entries(value).flatMap(([key, child]) => keys(child, prefix ? `${prefix}.${key}` : key));
}

describe('translation catalogs', () => {
  it('have the same keys in Arabic and English', () => {
    const read = (locale: string) => JSON.parse(fs.readFileSync(path.join(process.cwd(), 'messages', `${locale}.json`), 'utf8'));
    expect(keys(read('ar')).sort()).toEqual(keys(read('en')).sort());
  });
});
