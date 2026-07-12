import fs from 'node:fs';
import path from 'node:path';
import {describe,expect,it} from 'vitest';
import {createEmptyField,duplicateBuilderField,emptyBuilderDraft,isFormEditable,moveBuilderField,recoverBuilderDraft,removeBuilderField,serializeBuilderDraft,updateBuilderField} from '@/features/administration/form-builder-utils';
import {addReferenceItem,archiveReferenceItem,canApprovePermanentDeletion,editReferenceItem,exportCsvDefinition,exportJsonDefinition,filterForms,moveReferenceItem,restoreReferenceItem,restoreRequiresConfirmation,sortForms,sortReferenceItems,type DemoForm,type ReferenceItem} from '@/features/administration/repository';

const form=(id:string,nameEn:string,version:number,status:DemoForm['status']='draft'):DemoForm=>({id,nameAr:nameEn,nameEn,module:'inspections',version,status,language:'bilingual',updatedAt:'2026-07-13',owner:'Owner'});
const reference=(id:string,labelEn:string,order:number):ReferenceItem=>({id,labelAr:labelEn,labelEn,code:id,order,active:true,archived:false,scope:'organization'});

describe('administration builder utilities',()=>{
  it('updates editable Arabic and English labels',()=>{const field=createEmptyField();const draft={...emptyBuilderDraft(),fields:[field]};const arabic=updateBuilderField(draft,field.id,'ar','العنوان');expect(updateBuilderField(arabic,field.id,'en','Title').fields[0]).toMatchObject({ar:'العنوان',en:'Title'});});
  it('duplicates, removes, and moves fields without mutating the original draft',()=>{const first={...createEmptyField(),id:'first',en:'First'};const second={...createEmptyField(),id:'second',en:'Second'};const draft={...emptyBuilderDraft(),fields:[first,second]};const duplicate=duplicateBuilderField(first);expect(duplicate.id).not.toBe(first.id);expect(removeBuilderField({...draft,fields:[...draft.fields,duplicate]},duplicate.id).fields).toHaveLength(2);const moved=moveBuilderField(draft,0,1);expect(moved.fields.map(field=>field.id)).toEqual(['second','first']);expect(moveBuilderField(moved,1,-1).fields.map(field=>field.id)).toEqual(['first','second']);expect(draft.fields.map(field=>field.id)).toEqual(['first','second']);});
  it('serializes local drafts and safely recovers from invalid localStorage JSON',()=>{const draft={...emptyBuilderDraft(),ar:'نموذج',fields:[createEmptyField()]};expect(recoverBuilderDraft(serializeBuilderDraft(draft))).toMatchObject({ar:'نموذج'});expect(recoverBuilderDraft('{not json')).toEqual(emptyBuilderDraft());});
  it('keeps published forms non-editable',()=>{expect(isFormEditable('published')).toBe(false);expect(isFormEditable('draft')).toBe(true);});
});

describe('administration library and workspace utilities',()=>{
  it('filters and sorts the form library',()=>{const forms=[form('b','Bravo',1),form('a','Alpha',3,'published')];expect(filterForms(forms,'alpha','inspections','published','bilingual')).toEqual([forms[1]]);expect(sortForms(forms,'alpha').map(value=>value.id)).toEqual(['a','b']);expect(sortForms(forms,'version').map(value=>value.id)).toEqual(['a','b']);});
  it('adds, edits, sorts, archives, restores, and reorders reference data immutably',()=>{const initial=[reference('b','Bravo',2),reference('a','Alpha',1)];const added=addReferenceItem(initial,reference('c','Charlie',3));const edited=editReferenceItem(added,'c',{labelEn:'Changed'});expect(edited.find(value=>value.id==='c')?.labelEn).toBe('Changed');expect(sortReferenceItems(initial,'name').map(value=>value.id)).toEqual(['a','b']);const moved=moveReferenceItem(initial,'b',-1);expect(moved.map(value=>value.id)).toEqual(['b','a']);expect(archiveReferenceItem(initial,'a').find(value=>value.id==='a')?.archived).toBe(true);expect(restoreReferenceItem(archiveReferenceItem(initial,'a'),'a').find(value=>value.id==='a')?.archived).toBe(false);expect(initial.map(value=>value.id)).toEqual(['b','a']);});
  it('requires explicit restore confirmation and disables incomplete deletion safeguards',()=>{expect(restoreRequiresConfirmation(null)).toBe(false);expect(restoreRequiresConfirmation('archived-1')).toBe(true);expect(canApprovePermanentDeletion({recordId:'x',requesterId:'r',reason:'',typedConfirmation:'',dependenciesChecked:false,backupConfirmed:false,reauthenticated:false,secondApprovalRequired:true,protectedRecord:false})).toBe(false);});
  it('generates JSON and CSV exports',()=>{const forms=[form('a','Alpha',1)];expect(JSON.parse(exportJsonDefinition(forms))).toEqual(forms);expect(exportCsvDefinition(forms)).toContain('name_en');expect(exportCsvDefinition(forms)).toContain('Alpha');});
});

describe('administration translations',()=>{
  it('keep Arabic and English administration keys aligned',()=>{const read=(locale:string)=>JSON.parse(fs.readFileSync(path.join(process.cwd(),'messages',`${locale}.json`),'utf8')).administration;expect(Object.keys(read('ar')).sort()).toEqual(Object.keys(read('en')).sort());});
});
