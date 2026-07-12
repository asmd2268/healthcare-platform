'use server';
import {headers} from 'next/headers';
import {redirect} from 'next/navigation';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';

export type AuthActionState={error:string|null};
const initialState:AuthActionState={error:null};
export {initialState};
const safeError=()=>({error:'authFailed'});
export async function signInAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const email=String(formData.get('email')??'').trim(); const password=String(formData.get('password')??''); const locale=String(formData.get('locale')??'ar');
  if(!email||!password)return safeError();
  try{const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.signInWithPassword({email,password});if(error)return safeError();}catch{return safeError();}
  redirect(`/${locale}/profile`);
}
export async function requestPasswordResetAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const email=String(formData.get('email')??'').trim();if(!email)return safeError();
  try{const requestHeaders=await headers();const origin=requestHeaders.get('origin')??requestHeaders.get('x-forwarded-host')??'http://localhost:3000';const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo:`${origin}/auth/callback?next=/ar/settings`});if(error)return safeError();return {error:null};}catch{return safeError();}
}
export async function updatePasswordAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const password=String(formData.get('password')??'');if(password.length<12)return safeError();try{const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.updateUser({password});return error?safeError():{error:null};}catch{return safeError();}
}
export async function signOutAction(formData:FormData){const locale=String(formData.get('locale')??'ar');try{const supabase=await createServerUserSupabaseClient();await supabase.auth.signOut();}finally{redirect(`/${locale}/login`);}}
