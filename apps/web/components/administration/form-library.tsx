'use client';

import {useEffect,useMemo,useState} from 'react';
import {useTranslations} from 'next-intl';
import {administrationRepository,exportJsonDefinition,filterForms,sortForms,type DemoForm,type FormSort} from '@/features/administration/repository';

function downloadText(name:string,text:string,type:string){
  const url=URL.createObjectURL(new Blob([text],{type}));
  const anchor=document.createElement('a'); anchor.href=url; anchor.download=name; anchor.click();
  window.setTimeout(()=>URL.revokeObjectURL(url),0);
}

export function FormLibrary(){
  const t=useTranslations('administration');
  const [forms,setForms]=useState<DemoForm[]>([]);
  const [query,setQuery]=useState(''); const [module,setModule]=useState('all'); const [status,setStatus]=useState('all'); const [language,setLanguage]=useState('all'); const [sort,setSort]=useState<FormSort>('alpha'); const [preview,setPreview]=useState<DemoForm|null>(null);
  useEffect(()=>{administrationRepository.forms().then(setForms)},[]);
  const shown=useMemo(()=>sortForms(filterForms(forms,query,module,status,language),sort),[forms,query,module,status,language,sort]);
  const update=(id:string,fn:(form:DemoForm)=>DemoForm)=>setForms(current=>current.map(form=>form.id===id?fn(form):form));
  const duplicate=(form:DemoForm)=>setForms(current=>[...current,{...form,id:crypto.randomUUID(),status:'draft',version:form.version+1,updatedAt:new Date().toISOString().slice(0,10)}]);
  const createVersion=(form:DemoForm)=>duplicate(form);
  return <section className="page"><h1>{t('library')}</h1><p>{t('placeholder')}</p>
    <div className="ui-toolbar"><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={t('search')}/>
      <select aria-label={t('module')} value={module} onChange={e=>setModule(e.target.value)}><option value="all">{t('all')}</option><option value="inspections">{t('inspections')}</option><option value="pharmacy">{t('pharmacy')}</option></select>
      <select aria-label={t('status')} value={status} onChange={e=>setStatus(e.target.value)}><option value="all">{t('all')}</option><option value="draft">{t('draft')}</option><option value="published">{t('published')}</option><option value="archived">{t('archived')}</option></select>
      <select aria-label={t('language')} value={language} onChange={e=>setLanguage(e.target.value)}><option value="all">{t('all')}</option><option value="bilingual">{t('bilingual')}</option></select>
      <select aria-label={t('sort')} value={sort} onChange={e=>setSort(e.target.value as FormSort)}><option value="alpha">{t('alphabetical')}</option><option value="version">{t('version')}</option></select>
    </div>
    {shown.map(form=><article className="ui-card" key={form.id}><strong>{form.nameAr} / {form.nameEn}</strong><p>{t('module')}: {form.module} · v{form.version} · {t('owner')}: {form.owner} · {t('updated')}: {form.updatedAt} · {t(form.status)}</p>
      <button disabled={form.status==='published'} title={form.status==='published'?t('publishedEditDisabled'):undefined}>{t('editDraft')}</button><button onClick={()=>setPreview(form)}>{t('preview')}</button><button onClick={()=>duplicate(form)}>{t('duplicate')}</button><button onClick={()=>update(form.id,current=>({...current,status:'archived'}))}>{t('archive')}</button><button onClick={()=>update(form.id,current=>({...current,status:'draft'}))}>{t('restore')}</button><button onClick={()=>createVersion(form)}>{t('createVersion')}</button><button onClick={()=>downloadText(`${form.id}.json`,exportJsonDefinition(form),'application/json')}>{t('json')}</button>
    </article>)}
    {preview&&<div role="dialog" className="ui-card"><strong>{t('preview')}: {preview.nameEn}</strong><p>{preview.nameAr} / {preview.nameEn}</p><button onClick={()=>setPreview(null)}>{t('remove')}</button></div>}
  </section>;
}
