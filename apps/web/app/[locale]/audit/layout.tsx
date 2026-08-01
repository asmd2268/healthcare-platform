import {requireModuleAccess} from '@/lib/commercial.server';

export default async function AuditModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('audit',locale);
  return children;
}
