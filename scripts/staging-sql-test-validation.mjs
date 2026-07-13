import fs from 'node:fs'; import path from 'node:path';
export function stripComments(text){return text.replace(/\/\*[\s\S]*?\*\//g,'').replace(/--[^\n]*/g,'')}
export function validateSqlTest(text,name='test'){const sql=stripComments(text);if(!/\b(BEGIN|START\s+TRANSACTION)\s*;/i.test(sql))throw new Error(`${name}: transaction start required`);if(!/\bROLLBACK\s*;/i.test(sql))throw new Error(`${name}: ROLLBACK required`);if(/\bCOMMIT\s*;/i.test(sql))throw new Error(`${name}: COMMIT prohibited`);if(/\b(DROP\s+(DATABASE|SCHEMA|TABLE)|TRUNCATE|ALTER\s+SYSTEM|PG_TERMINATE_BACKEND)\b/i.test(sql))throw new Error(`${name}: destructive SQL prohibited`)}
export function executableFiles(directory){return fs.readdirSync(directory).filter(x=>x.endsWith('.executable.sql')).sort().map(x=>path.join(directory,x))}
if(process.argv[1]===new URL(import.meta.url).pathname){const file=process.argv[2];if(!file)throw new Error('SQL test file is required');validateSqlTest(fs.readFileSync(file,'utf8'),file)}
