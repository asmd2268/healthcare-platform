import {getTranslations} from 'next-intl/server';
import {LoginForm} from '@/components/auth/login-form';

export default async function LoginPage({params}:{params:Promise<{locale:string}>}) { const t = await getTranslations('auth'); const {locale}=await params; return <section className="page narrow"><h1>{t('title')}</h1><p>{t('body')}</p><LoginForm locale={locale}/></section>; }
