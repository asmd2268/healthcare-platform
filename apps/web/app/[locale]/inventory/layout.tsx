import {requireModuleAccess} from '@/lib/commercial.server';

export default async function InventoryModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('inventory',locale);
  return children;
}
