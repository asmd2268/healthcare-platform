import {CapaWorkspace} from '@/components/capa/workspace';

export default async function CapaView({params}:{params:Promise<{view:string}>}) {
  const {view}=await params;
  const allowed=['dashboard','detail','actions','rootCause','effectiveness'] as const;
  const selected=allowed.includes(view as typeof allowed[number]) ? view as typeof allowed[number] : 'detail';
  return <CapaWorkspace view={selected}/>;
}
