import {requireModuleAccess} from '@/lib/commercial.server';

export default async function PoliciesModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('policies',locale);
  return children;
}
