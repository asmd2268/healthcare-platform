import {getTranslations} from 'next-intl/server';
import {Alert, Input} from '@healthcare/ui';

export default async function LoginPage() { const t = await getTranslations('auth'); return <section className="page narrow"><h1>{t('title')}</h1><p>{t('body')}</p><label>{t('email')}<Input disabled type="email" /></label><label>{t('password')}<Input disabled type="password" /></label><Alert>{t('unavailable')}</Alert></section>; }
