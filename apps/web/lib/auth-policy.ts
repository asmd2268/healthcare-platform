export const protectedRouteSegments=new Set(['settings','profile','audit','administration','inspections']);
export const authenticationRequired=(hasSupabaseConfig:boolean,hasVerifiedUser:boolean)=>!hasSupabaseConfig||!hasVerifiedUser;
