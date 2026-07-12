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
