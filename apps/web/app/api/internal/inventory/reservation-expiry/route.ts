import {NextResponse,type NextRequest} from 'next/server';
import {createAdminSupabaseClient} from '@/lib/supabase-admin.server';
import {
  hasInventoryReservationExpirySchedulerAuthorization,
  invokeInventoryReservationExpiryScheduler,
  loadInventoryReservationExpirySchedulerConfiguration
} from '@/lib/inventory-reservation-expiry-scheduler.server';

export const runtime='nodejs';
export const dynamic='force-dynamic';
export const maxDuration=60;

const noStore={'Cache-Control':'no-store'};

export async function GET(request:NextRequest){
  let configuration;
  try { configuration=loadInventoryReservationExpirySchedulerConfiguration(); }
  catch { return NextResponse.json({error:'Scheduler unavailable.'},{status:503,headers:noStore}); }

  if(!hasInventoryReservationExpirySchedulerAuthorization(request.headers.get('authorization'),configuration.CRON_SECRET)){
    return NextResponse.json({error:'Unauthorized.'},{status:401,headers:noStore});
  }

  try {
    const result=await invokeInventoryReservationExpiryScheduler(configuration,createAdminSupabaseClient());
    return NextResponse.json(result,{status:200,headers:noStore});
  } catch {
    // Do not expose configuration, database, automation-principal, or service-role details.
    return NextResponse.json({error:'Scheduler unavailable.'},{status:503,headers:noStore});
  }
}

export async function POST(_request:NextRequest){
  return NextResponse.json({error:'Method not allowed.'},{status:405,headers:noStore});
}

export async function HEAD(){
  return new NextResponse(null,{status:405,headers:noStore});
}
