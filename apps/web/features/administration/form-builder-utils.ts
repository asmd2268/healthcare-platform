import type {DynamicFieldType, FormStatus} from '@healthcare/platform-administration';

export const formDraftStorageKey='platform-admin-form-draft';
export const supportedFieldTypes:DynamicFieldType[]=['text','long_text','number','decimal','percentage','date','time','datetime','yes_no','single_choice','multiple_choice','dropdown','checkbox','rating','score','file','image','signature','user_selector','department_selector','facility_selector','medication_selector','reference_record_selector','calculated'];
export type ContentLanguage='arabic'|'english'|'bilingual';
export type ConfidentialityLevel='normal'|'confidential'|'restricted';
export type BuilderField={id:string;type:DynamicFieldType;ar:string;en:string;required:boolean;readOnly:boolean;confidentiality:ConfidentialityLevel;searchable:boolean;sortable:boolean;filterable:boolean;exportable:boolean;importable:boolean;helpAr:string;helpEn:string;defaultValue:string;validation:string};
export type BuilderDraft={ar:string;en:string;descriptionAr:string;descriptionEn:string;module:string;language:ContentLanguage;preview:ContentLanguage;fields:BuilderField[]};
export const emptyBuilderDraft=():BuilderDraft=>({ar:'',en:'',descriptionAr:'',descriptionEn:'',module:'platform',language:'bilingual',preview:'bilingual',fields:[]});
let fallbackCounter=0;
export const createStableId=()=>globalThis.crypto?.randomUUID?.()??`field-${Date.now()}-${++fallbackCounter}`;
export const createEmptyField=():BuilderField=>({id:createStableId(),type:'text',ar:'',en:'',required:false,readOnly:false,confidentiality:'normal',searchable:true,sortable:false,filterable:false,exportable:true,importable:true,helpAr:'',helpEn:'',defaultValue:'',validation:''});
export const duplicateBuilderField=(field:BuilderField):BuilderField=>({...field,id:createStableId()});
export const updateBuilderField=(draft:BuilderDraft,id:string,key:keyof BuilderField,value:string|boolean):BuilderDraft=>({...draft,fields:draft.fields.map(field=>field.id===id?{...field,[key]:value}:field)});
export const removeBuilderField=(draft:BuilderDraft,id:string):BuilderDraft=>({...draft,fields:draft.fields.filter(field=>field.id!==id)});
export const moveBuilderField=(draft:BuilderDraft,index:number,direction:-1|1):BuilderDraft=>{const target=index+direction;if(index<0||target<0||target>=draft.fields.length)return draft;const fields=[...draft.fields];[fields[index],fields[target]]=[fields[target],fields[index]];return {...draft,fields};};
export const serializeBuilderDraft=(draft:BuilderDraft)=>JSON.stringify(draft);
export const recoverBuilderDraft=(value:string|null):BuilderDraft=>{if(!value)return emptyBuilderDraft();try{const parsed=JSON.parse(value) as Partial<BuilderDraft>;if(!Array.isArray(parsed.fields))throw new Error('Invalid form draft');return {...emptyBuilderDraft(),...parsed,fields:parsed.fields as BuilderField[]}}catch{return emptyBuilderDraft()}};
export const isFormEditable=(status:FormStatus)=>status!=='published';
