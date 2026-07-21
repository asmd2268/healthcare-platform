import 'server-only';
import {createHash, timingSafeEqual} from 'node:crypto';
import {z} from 'zod';

const strictPositiveInteger=(defaultValue:number,maxValue:number)=>z.preprocess(value=>{
  if(value===undefined||value==='')return defaultValue;
  return typeof value==='string'&&/^\d+$/.test(value)?Number(value):value;
},z.number().int().min(1).max(maxValue));

const schedulerEnvironmentSchema=z.object({
  NEXT_PUBLIC_SUPABASE_URL:z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY:z.string().min(1),
  CRON_SECRET:z.string().min(16).refine(value=>value.trim()===value&&!/[\s,]/.test(value),'Invalid cron secret.'),
  INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID:z.string().uuid(),
  INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:strictPositiveInteger(100,1000),
  INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:strictPositiveInteger(10,100)
}).superRefine((value,context)=>{
  if(value.INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT*value.INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES>1000){
    context.addIssue({code:z.ZodIssueCode.custom,path:['INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES'],message:'Inventory reservation expiry drain limit is invalid.'});
  }
});

export type InventoryReservationExpirySchedulerConfiguration=z.infer<typeof schedulerEnvironmentSchema>;

export interface ReservationExpiryRpcClient {
  rpc(name:'expire_inventory_transfer_reservations',args:{p_actor:string;p_limit:number}):PromiseLike<{data:unknown;error:{message?:string}|null}>;
}

export interface ReservationExpirySchedulerInvocationResult {
  processed:number;
  batches:number;
  drainLimitReached:boolean;
}

export class ReservationExpirySchedulerInvocationError extends Error {
  constructor(){super('Reservation expiry scheduler invocation failed.');}
}

export function loadInventoryReservationExpirySchedulerConfiguration(environment:Record<string,string|undefined>=process.env):InventoryReservationExpirySchedulerConfiguration {
  return schedulerEnvironmentSchema.parse({
    NEXT_PUBLIC_SUPABASE_URL:environment.NEXT_PUBLIC_SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY:environment.SUPABASE_SERVICE_ROLE_KEY,
    CRON_SECRET:environment.CRON_SECRET,
    INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID:environment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,
    INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:environment.INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT,
    INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:environment.INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES
  });
}

/** Compares fixed-size digests so an authorization failure reveals no secret prefix. */
export function hasInventoryReservationExpirySchedulerAuthorization(authorizationHeader:string|null,cronSecret:string):boolean {
  if(!/^Bearer [^\s,]+$/.test(authorizationHeader??''))return false;
  const expected=createHash('sha256').update(`Bearer ${cronSecret}`).digest();
  const received=createHash('sha256').update(authorizationHeader??'').digest();
  return timingSafeEqual(expected,received);
}

/**
 * The configured principal is passed to the trusted database worker. The worker
 * resolves its registered purpose and scope before every expiry effect, and its
 * reservation-specific command key makes repeated scheduler delivery idempotent.
 */
export async function invokeInventoryReservationExpiryScheduler(
  configuration:InventoryReservationExpirySchedulerConfiguration,
  client:ReservationExpiryRpcClient
):Promise<ReservationExpirySchedulerInvocationResult> {
  let processed=0;
  let batches=0;
  let latestBatchCount=0;
  while(batches<configuration.INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES){
    const {data,error}=await client.rpc('expire_inventory_transfer_reservations',{
      p_actor:configuration.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,
      p_limit:configuration.INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT
    });
    if(error||typeof data!=='number'||!Number.isInteger(data)||data<0)throw new ReservationExpirySchedulerInvocationError();
    latestBatchCount=data;
    processed+=data;
    batches+=1;
    if(data<configuration.INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT)break;
  }
  return {processed,batches,drainLimitReached:batches===configuration.INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES&&latestBatchCount===configuration.INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT};
}
