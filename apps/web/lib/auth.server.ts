import 'server-only';
import type {User} from '@supabase/supabase-js';
import {createServerUserSupabaseClient} from './supabase-server';

export class AuthenticationRequiredError extends Error { constructor(){super('Authentication is required.');} }
export class AuthorizationDeniedError extends Error { constructor(){super('Authorization is denied.');} }

export async function getAuthenticatedUser():Promise<User|null>{
  const supabase=await createServerUserSupabaseClient();
  const {data,error}=await supabase.auth.getUser();
  if(error) return null;
  return data.user;
}
export async function requireAuthenticatedUser(){const user=await getAuthenticatedUser();if(!user)throw new AuthenticationRequiredError();return user;}
export async function loadCurrentUserProfile(){const user=await requireAuthenticatedUser();const supabase=await createServerUserSupabaseClient();const {data,error}=await supabase.from('user_profiles').select('id, display_name, preferred_locale').eq('id',user.id).maybeSingle();if(error)throw new AuthorizationDeniedError();return {user,profile:data};}
export async function requirePlatformPermission(permission:string,scope:{tenantId:string;organizationId?:string|null;facilityId?:string|null}){
  await requireAuthenticatedUser(); const supabase=await createServerUserSupabaseClient();
  const {data:scopeAllowed,error:scopeError}=await supabase.rpc('scope_allowed',{target_tenant:scope.tenantId,target_organization:scope.organizationId??null,target_facility:scope.facilityId??null});
  const {data:permissionAllowed,error:permissionError}=await supabase.rpc('has_platform_permission',{permission_key:permission,target_tenant:scope.tenantId,target_organization:scope.organizationId??null,target_facility:scope.facilityId??null});
  if(scopeError||permissionError||!scopeAllowed||!permissionAllowed)throw new AuthorizationDeniedError();
}
