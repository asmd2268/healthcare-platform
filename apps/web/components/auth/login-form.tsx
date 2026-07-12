'use client';
import {useActionState} from 'react';
import {useTranslations} from 'next-intl';
import {initialState,requestPasswordResetAction,signInAction} from '@/app/[locale]/login/actions';

export function LoginForm({locale}:{locale:string}){const t=useTranslations('auth');const [signInState,signIn]=useActionState(signInAction,initialState);const [resetState,reset]=useActionState(requestPasswordResetAction,initialState);return <><form action={signIn}><input type="hidden" name="locale" value={locale}/><label>{t('email')}<input name="email" type="email" autoComplete="email" required/></label><label>{t('password')}<input name="password" type="password" autoComplete="current-password" required/></label><button type="submit">{t('submit')}</button>{signInState.error&&<p role="alert">{t(signInState.error)}</p>}</form><form action={reset}><label>{t('email')}<input name="email" type="email" autoComplete="email" required/></label><button type="submit">{t('resetRequest')}</button>{resetState.error&&<p role="alert">{t(resetState.error)}</p>}{!resetState.error&&<p>{t('resetRequestHint')}</p>}</form></>}
