import {requireModuleAccess} from '@/lib/commercial.server';

export default async function CapaModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('capa',locale);
  return children;
}
