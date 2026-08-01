import {requireModuleAccess} from '@/lib/commercial.server';

export default async function InspectionsModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('inspections',locale);
  return children;
}
