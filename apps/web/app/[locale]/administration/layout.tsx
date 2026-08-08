import {requireModuleAccess} from '@/lib/commercial.server';

export default async function AdministrationModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('administration',locale);
  return children;
}
