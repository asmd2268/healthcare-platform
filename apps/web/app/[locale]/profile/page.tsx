import {getTranslations} from 'next-intl/server';
import {loadCurrentUserProfile} from '@/lib/auth.server';
export const dynamic='force-dynamic';
export default async function ProfilePage() { const t = await getTranslations('profile'); const {user,profile}=await loadCurrentUserProfile(); return <section className="page"><h1>{t('title')}</h1><p>{t('body')}</p><p>{t('signedInAs',{email:user.email??profile?.display_name??''})}</p></section>; }
