export const protectedRouteSegments=new Set(['settings','profile','audit','administration','inspections','inventory']);
export const authenticationRequired=(hasSupabaseConfig:boolean,hasVerifiedUser:boolean)=>!hasSupabaseConfig||!hasVerifiedUser;
