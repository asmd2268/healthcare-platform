'use client';
import {useTranslations} from 'next-intl';
import {Card, Badge} from '@healthcare/ui';
const metrics = ['total','completed','drafts','average','failed','openFindings','critical'] as const;
export function InspectionDashboard(){const t=useTranslations('inspections.dashboard'); return <section className="page"><h1>{t('title')}</h1><p>{t('sample')}</p><div className="metrics">{metrics.map((m,i)=><Card key={m}><strong>{t(m)}</strong><Badge>{i===3?'—':'0'}</Badge></Card>)}</div></section>}
