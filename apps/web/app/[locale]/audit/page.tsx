import {getTranslations} from 'next-intl/server';
import {Alert} from '@healthcare/ui';
import {getCurrentTenantContext} from '@/lib/tenant-context.server';
import {listRecentAuditEvents} from '@/features/audit/supabase-repository.server';
export const dynamic='force-dynamic';
export default async function AuditPage() { const t = await getTranslations('audit'); const context=await getCurrentTenantContext(); if(!context)return <section className="page"><h1>{t('title')}</h1><Alert>{t('noTenantContext')}</Alert></section>; try{const events=await listRecentAuditEvents(context);return <section className="page"><h1>{t('title')}</h1><p>{t('body')}</p>{events.length?events.map(event=><article className="ui-card" key={event.id}><p>{event.action}</p><p>{event.created_at}</p></article>):<Alert>{t('placeholder')}</Alert>}</section>}catch{return <section className="page"><h1>{t('title')}</h1><Alert>{t('databaseUnavailable')}</Alert></section>;} }
