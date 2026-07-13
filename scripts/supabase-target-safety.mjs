import process from 'node:process';
import {pathToFileURL} from 'node:url';

const overridePhrase='I_UNDERSTAND_THIS_IS_PRODUCTION';
export function projectRefFromUrl(value){const url=new URL(value);return url.hostname.endsWith('.supabase.co')?url.hostname.slice(0,-'.supabase.co'.length):url.hostname;}
export function validateSupabaseTarget(environment,action='check'){
  const required=['NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','APP_BASE_URL'];
  const missing=required.filter(key=>!environment[key]);if(missing.length)throw new Error(`Missing required staging variables: ${missing.join(', ')}`);
  if(action==='bootstrap'&&(!environment.SUPABASE_SERVICE_ROLE_KEY||!environment.PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION))throw new Error('Bootstrap validation requires admin-only variables from the secret manager.');
  if((action==='seed'||action==='sql-tests')&&!environment.DATABASE_URL)throw new Error('This validation requires DATABASE_URL from the secret manager.');
  const stage=environment.SUPABASE_ENV;if(stage!=='local'&&stage!=='staging')throw new Error('SUPABASE_ENV must be explicitly local or staging.');
  const projectRef=projectRefFromUrl(environment.NEXT_PUBLIC_SUPABASE_URL);const databaseHost=environment.DATABASE_URL?projectRefFromUrl(environment.DATABASE_URL):'';const productionLooking=stage==='production'||/(^|[-_.])(prod|production|live)([-_.]|$)/i.test(projectRef)||/(^|[-_.])(prod|production|live)([-_.]|$)/i.test(databaseHost);
  const overridden=environment.ALLOW_PRODUCTION_SUPABASE_COMMANDS===overridePhrase;
  if(productionLooking&&!overridden)throw new Error('Refusing a production-looking Supabase target without the explicit override.');
  if(action==='reset'&&stage!=='local'&&stage!=='staging')throw new Error('Reset is permitted only for explicit local or staging environments.');
  return {projectRef,stage,action,overridden};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){const action=process.argv[2]??'check';try{const target=validateSupabaseTarget(process.env,action);console.log(`Supabase target: ${target.projectRef} (${target.stage}); action: ${target.action}`);if(action==='reset')console.log('Safety check passed. Run the reset command manually only after a confirmed staging backup.');}catch(error){console.error(error instanceof Error?error.message:'Supabase target validation failed.');process.exitCode=1;}}
