import {getTranslations} from 'next-intl/server';
import {LoadingState} from '@healthcare/ui';
export default async function InventoryLoading() { const t = await getTranslations('inventory'); return <section className="page"><LoadingState>{t('loading')}</LoadingState></section>; }
