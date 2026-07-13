import {describe,it,expect} from 'vitest';
// @ts-expect-error JavaScript runner helper is exercised directly by this test.
import {validateSqlTest} from '../../../scripts/staging-sql-test-validation.mjs';
describe('staging SQL test convention',()=>{it('accepts transactional SQL',()=>expect(()=>validateSqlTest('begin; select 1; rollback;')).not.toThrow());it('rejects unsafe or incomplete SQL',()=>{for(const sql of ['select 1;','begin; select 1;','begin; commit;','begin; drop table x; rollback;'])expect(()=>validateSqlTest(sql)).toThrow()})});
