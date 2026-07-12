import {validatePermanentDeletion,type DeletionRequest} from '@healthcare/platform-administration';
export type DemoForm={id:string;nameAr:string;nameEn:string;module:string;version:number;status:'draft'|'published'|'archived';language:'bilingual';updatedAt:string;owner:string};
export type ReferenceItem={id:string;labelAr:string;labelEn:string;code:string;order:number;active:boolean;archived:boolean;scope:string};
export type FormSort='alpha'|'version';
export const demoArchivedRecords=[
  {id:'archived-1',type:'Form definition',label:'Archived inspection template',archivedAt:'2026-07-01'},
  {id:'archived-2',type:'Reference value',label:'Archived department value',archivedAt:'2026-06-28'}
];
export const demoDeletionRequest={recordId:'demo-record',requesterId:'demo-requester',reason:'',typedConfirmation:'',dependenciesChecked:false,backupConfirmed:false,reauthenticated:false,secondApprovalRequired:true,secondApproverId:undefined,protectedRecord:false};
export function filterForms(forms:DemoForm[],query:string,module='all',status='all',language='all'){
  const needle=query.trim().toLocaleLowerCase();
  return forms.filter(f=>(module==='all'||f.module===module)&&(status==='all'||f.status===status)&&(language==='all'||f.language===language)&&(!needle||`${f.nameAr} ${f.nameEn}`.toLocaleLowerCase().includes(needle)));
}
export function sortForms(forms:DemoForm[],sort:FormSort){
  return [...forms].sort((a,b)=>sort==='version'?b.version-a.version:a.nameEn.localeCompare(b.nameEn));
}
export function exportJsonDefinition(value:unknown){return JSON.stringify(value,null,2)}
export function exportCsvDefinition(forms:DemoForm[]){
  const rows=[['id','name_ar','name_en','module','version','status','language','updated_at','owner'],...forms.map(f=>[f.id,f.nameAr,f.nameEn,f.module,String(f.version),f.status,f.language,f.updatedAt,f.owner])];
  return rows.map(row=>row.map(value=>`"${value.replaceAll('"','""')}"`).join(',')).join('\n');
}
export const addReferenceItem=(items:ReferenceItem[],item:ReferenceItem)=>[...items,item];
export const editReferenceItem=(items:ReferenceItem[],id:string,changes:Partial<ReferenceItem>)=>items.map(item=>item.id===id?{...item,...changes}:item);
export const sortReferenceItems=(items:ReferenceItem[],sort:'name'|'order')=>[...items].sort((a,b)=>sort==='order'?a.order-b.order:a.labelEn.localeCompare(b.labelEn));
export const moveReferenceItem=(items:ReferenceItem[],id:string,direction:-1|1)=>{const index=items.findIndex(item=>item.id===id);const target=index+direction;if(index<0||target<0||target>=items.length)return items;const next=[...items];[next[index],next[target]]=[next[target],next[index]];return next.map((item,order)=>({...item,order:order+1}));};
export const archiveReferenceItem=(items:ReferenceItem[],id:string)=>editReferenceItem(items,id,{archived:true});
export const restoreReferenceItem=(items:ReferenceItem[],id:string)=>editReferenceItem(items,id,{archived:false});
export const restoreRequiresConfirmation=(selectedRecordId:string|null)=>selectedRecordId!==null;
export const canApprovePermanentDeletion=(request:DeletionRequest)=>{try{validatePermanentDeletion(request);return true}catch{return false}};
export const administrationRepository={
  async forms():Promise<DemoForm[]>{return [
    {id:'form-1',nameAr:'نموذج تفتيش تجريبي',nameEn:'Demo Inspection Form',module:'inspections',version:1,status:'published',language:'bilingual',updatedAt:'2026-07-13',owner:'Demo Owner'},
    {id:'form-2',nameAr:'نموذج صيدلية تجريبي',nameEn:'Demo Pharmacy Form',module:'pharmacy',version:2,status:'draft',language:'bilingual',updatedAt:'2026-07-12',owner:'Platform Team'},
    {id:'form-3',nameAr:'نموذج قديم',nameEn:'Archived Demo Form',module:'inspections',version:3,status:'archived',language:'bilingual',updatedAt:'2026-07-01',owner:'Quality Team'}
  ]},
  async reference():Promise<ReferenceItem[]>{return [
    {id:'ref-1',labelAr:'قسم تجريبي',labelEn:'Demo Department',code:'DEMO',order:1,active:true,archived:false,scope:'organization'},
    {id:'ref-2',labelAr:'قسم الصيدلية',labelEn:'Pharmacy Department',code:'PHARM',order:2,active:true,archived:false,scope:'organization'}
  ]}
};
