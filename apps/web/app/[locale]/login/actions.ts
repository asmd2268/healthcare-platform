'use server';
import {redirect} from 'next/navigation';
import {createServerUserSupabaseClient} from '@/lib/supabase-server';
import {serverUserEnvironment} from '@/lib/env';
import {passwordResetRedirect,safeLocale} from '@/lib/auth-redirect';

export type AuthActionState={error:string|null};
const initialState:AuthActionState={error:null};
export {initialState};
const safeError=()=>({error:'authFailed'});
export async function signInAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const email=String(formData.get('email')??'').trim(); const password=String(formData.get('password')??''); const locale=safeLocale(formData.get('locale'));
  if(!email||!password)return safeError();
  try{const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.signInWithPassword({email,password});if(error)return safeError();}catch{return safeError();}
  redirect(`/${locale}/profile`);
}
export async function requestPasswordResetAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const email=String(formData.get('email')??'').trim();const locale=safeLocale(formData.get('locale'));if(!email||!serverUserEnvironment.APP_BASE_URL)return safeError();
  try{const redirectTo=passwordResetRedirect(serverUserEnvironment.APP_BASE_URL,locale);const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo});if(error)return safeError();return {error:null};}catch{return safeError();}
}
export async function updatePasswordAction(_state:AuthActionState,formData:FormData):Promise<AuthActionState>{
  const password=String(formData.get('password')??'');if(password.length<12)return safeError();try{const supabase=await createServerUserSupabaseClient();const {error}=await supabase.auth.updateUser({password});return error?safeError():{error:null};}catch{return safeError();}
}
export async function signOutAction(formData:FormData){const locale=String(formData.get('locale')??'ar');try{const supabase=await createServerUserSupabaseClient();await supabase.auth.signOut();}finally{redirect(`/${locale}/login`);}}
