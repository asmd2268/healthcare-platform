import {requireModuleAccess} from '@/lib/commercial.server';

export default async function MedicationErrorsModuleLayout({children,params}:{children:React.ReactNode;params:Promise<{locale:string}>}) {
  const {locale}=await params;
  await requireModuleAccess('medication_errors',locale);
  return children;
}
