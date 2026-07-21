import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import type {NextRequest} from 'next/server';

const {rpc}=vi.hoisted(()=>({rpc:vi.fn()}));

vi.mock('@/lib/supabase-admin.server',()=>({createAdminSupabaseClient:()=>({rpc})}));

import {
  ReservationExpirySchedulerInvocationError,
  hasInventoryReservationExpirySchedulerAuthorization,
  invokeInventoryReservationExpiryScheduler,
  loadInventoryReservationExpirySchedulerConfiguration
} from '@/lib/inventory-reservation-expiry-scheduler.server';
import * as reservationExpiryRoute from '@/app/api/internal/inventory/reservation-expiry/route';

const validEnvironment={
  NEXT_PUBLIC_SUPABASE_URL:'https://scheduler-test.invalid',
  SUPABASE_SERVICE_ROLE_KEY:'server-only-test-key',
  CRON_SECRET:'scheduler-secret-at-least-sixteen-characters',
  INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID:'71000000-0000-0000-0000-000000000140'
};

const schedulerEnvironmentKeys=[
  'NEXT_PUBLIC_SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'CRON_SECRET',
  'INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID',
  'INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT',
  'INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES'
] as const;
const originalEnvironment=Object.fromEntries(schedulerEnvironmentKeys.map(key=>[key,process.env[key]]));

function setSchedulerEnvironment(environment:Record<string,string|undefined>=validEnvironment){
  for(const key of schedulerEnvironmentKeys){
    const value=environment[key];
    if(value===undefined)delete process.env[key]; else process.env[key]=value;
  }
}

beforeEach(()=>{
  vi.clearAllMocks();
  setSchedulerEnvironment();
});

afterEach(()=>setSchedulerEnvironment(originalEnvironment));

describe('inventory reservation expiry scheduler boundary',()=>{
  it('rejects incomplete, malformed, and out-of-range deployment configuration',()=>{
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID:''})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID:'not-a-uuid'})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,NEXT_PUBLIC_SUPABASE_URL:''})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,SUPABASE_SERVICE_ROLE_KEY:''})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,CRON_SECRET:''})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,CRON_SECRET:'                '})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'0'})).toThrow();
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'1001'})).toThrow();
    for(const value of [' 1','+1','1.0','1e2','-1','1,2','999999999999999999999999999999']){
      expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:value})).toThrow();
    }
    expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'101',INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:'10'})).toThrow();
    for(const value of ['0',' 1','+1','1.0','1e2','-1','1,2','999999999999999999999999999999']){
      expect(()=>loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:value})).toThrow();
    }
  });

  it('uses a configured automation principal and bounded batch limit, never a caller actor',async()=>{
    const configuration=loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'12'});
    const calls:Array<{name:string;args:unknown}>=[];
    const processed=await invokeInventoryReservationExpiryScheduler(configuration,{rpc:async(name,args)=>{calls.push({name,args});return {data:4,error:null};}});
    expect(processed).toEqual({processed:4,batches:1,drainLimitReached:false});
    expect(calls).toEqual([{name:'expire_inventory_transfer_reservations',args:{p_actor:validEnvironment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,p_limit:12}}]);
  });

  it('rejects missing, malformed, duplicated, and incorrect scheduler authorization without accepting prefixes',()=>{
    expect(hasInventoryReservationExpirySchedulerAuthorization(null,validEnvironment.CRON_SECRET)).toBe(false);
    expect(hasInventoryReservationExpirySchedulerAuthorization(`Bearer ${validEnvironment.CRON_SECRET.slice(0,-1)}`,validEnvironment.CRON_SECRET)).toBe(false);
    expect(hasInventoryReservationExpirySchedulerAuthorization(`bearer ${validEnvironment.CRON_SECRET}`,validEnvironment.CRON_SECRET)).toBe(false);
    expect(hasInventoryReservationExpirySchedulerAuthorization(`Bearer ${validEnvironment.CRON_SECRET} extra`,validEnvironment.CRON_SECRET)).toBe(false);
    expect(hasInventoryReservationExpirySchedulerAuthorization(`Bearer ${validEnvironment.CRON_SECRET}, Bearer other-secret`,validEnvironment.CRON_SECRET)).toBe(false);
    expect(hasInventoryReservationExpirySchedulerAuthorization(`Bearer ${validEnvironment.CRON_SECRET}`,validEnvironment.CRON_SECRET)).toBe(true);
  });

  it.each([
    'Automation identity is not registered for purpose',
    'Automation identity is inactive',
    'Automation identity purpose is invalid',
    'Automation identity scope is not authorized'
  ])('fails closed when the trusted RPC rejects %s',async message=>{
    const configuration=loadInventoryReservationExpirySchedulerConfiguration(validEnvironment);
    await expect(invokeInventoryReservationExpiryScheduler(configuration,{rpc:async()=>({data:null,error:{message}})})).rejects.toBeInstanceOf(ReservationExpirySchedulerInvocationError);
    await expect(invokeInventoryReservationExpiryScheduler(configuration,{rpc:async()=>({data:'not-a-count',error:null})})).rejects.toBeInstanceOf(ReservationExpirySchedulerInvocationError);
  });

  it('drains bounded batches and exposes a backlog signal without changing the database idempotency boundary',async()=>{
    const configuration=loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'2',INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:'3'});
    const calls:Array<unknown>=[];
    const results=[2,2,1];
    const client={rpc:async(_name:'expire_inventory_transfer_reservations',args:{p_actor:string;p_limit:number})=>{calls.push(args);return {data:results.shift()!,error:null};}};
    await expect(invokeInventoryReservationExpiryScheduler(configuration,client)).resolves.toEqual({processed:5,batches:3,drainLimitReached:false});
    expect(calls).toEqual([
      {p_actor:validEnvironment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,p_limit:2},
      {p_actor:validEnvironment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,p_limit:2},
      {p_actor:validEnvironment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,p_limit:2}
    ]);
  });

  it('reports a bounded drain limit for monitoring when every permitted batch is full',async()=>{
    const configuration=loadInventoryReservationExpirySchedulerConfiguration({...validEnvironment,INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT:'2',INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES:'3'});
    const client={rpc:async()=>({data:2,error:null})};
    await expect(invokeInventoryReservationExpiryScheduler(configuration,client)).resolves.toEqual({processed:6,batches:3,drainLimitReached:true});
  });

  it('protects the HTTP route, ignores actor-shaped request input, and returns generic operational failures',async()=>{
    rpc.mockResolvedValue({data:0,error:null});
    const validRequest=new Request(`https://example.invalid/api/internal/inventory/reservation-expiry?p_actor=00000000-0000-0000-0000-000000000001`,{
      headers:{authorization:`Bearer ${validEnvironment.CRON_SECRET}`,'x-actor':'00000000-0000-0000-0000-000000000001'}
    });
    const success=await reservationExpiryRoute.GET(validRequest as NextRequest);
    expect(success.status).toBe(200);
    expect(await success.json()).toEqual({processed:0,batches:1,drainLimitReached:false});
    expect(rpc).toHaveBeenCalledWith('expire_inventory_transfer_reservations',{
      p_actor:validEnvironment.INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID,p_limit:100
    });

    const duplicatedHeaders=new Headers();
    duplicatedHeaders.append('authorization',`Bearer ${validEnvironment.CRON_SECRET}`);
    duplicatedHeaders.append('authorization','Bearer duplicate');
    for(const authorization of [undefined,`Bearer ${validEnvironment.CRON_SECRET} extra`,duplicatedHeaders.get('authorization')]){
      const headers=new Headers();
      if(authorization)headers.set('authorization',authorization);
      const response=await reservationExpiryRoute.GET(new Request('https://example.invalid/api/internal/inventory/reservation-expiry',{headers}) as NextRequest);
      expect(response.status).toBe(401);
      await expect(response.json()).resolves.toEqual({error:'Unauthorized.'});
    }
    expect(rpc).toHaveBeenCalledTimes(1);

    expect((await reservationExpiryRoute.POST(new Request('https://example.invalid/api/internal/inventory/reservation-expiry',{
      method:'POST',body:JSON.stringify({p_actor:'00000000-0000-0000-0000-000000000001'}),headers:{'content-type':'application/json'}
    }) as NextRequest)).status).toBe(405);
    expect((await reservationExpiryRoute.HEAD()).status).toBe(405);
    expect('PUT' in reservationExpiryRoute).toBe(false);

    rpc.mockResolvedValueOnce({data:null,error:{message:'automation identity scope is invalid'}});
    const failed=await reservationExpiryRoute.GET(new Request('https://example.invalid/api/internal/inventory/reservation-expiry',{headers:{authorization:`Bearer ${validEnvironment.CRON_SECRET}`}}) as NextRequest);
    expect(failed.status).toBe(503);
    await expect(failed.json()).resolves.toEqual({error:'Scheduler unavailable.'});

    setSchedulerEnvironment({...validEnvironment,CRON_SECRET:undefined});
    const unavailable=await reservationExpiryRoute.GET(new Request('https://example.invalid/api/internal/inventory/reservation-expiry') as NextRequest);
    expect(unavailable.status).toBe(503);
    await expect(unavailable.json()).resolves.toEqual({error:'Scheduler unavailable.'});
  });
});
