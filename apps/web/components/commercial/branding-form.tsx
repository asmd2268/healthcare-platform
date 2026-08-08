'use client';
import {useActionState} from 'react';
import {useLocale,useTranslations} from 'next-intl';
import type {BrandingSettings} from '@healthcare/branding';
import {updateBrandingAction,type BrandingActionState} from '@/app/[locale]/settings/actions';

const initialBrandingActionState:BrandingActionState={status:'idle'};

export function BrandingForm({branding,scopeLevel,revision,whiteLabelEnabled}:{branding:BrandingSettings;scopeLevel:'organization'|'facility';revision:number|null;whiteLabelEnabled:boolean}){
  const t=useTranslations('commercial');const locale=useLocale();const [state,action,pending]=useActionState(updateBrandingAction,initialBrandingActionState);
  return <form action={action} className="commercial-form ui-card">
    <input type="hidden" name="locale" value={locale}/><input type="hidden" name="scopeLevel" value={scopeLevel}/><input type="hidden" name="expectedRevision" value={revision??''}/>
    <h2>{t(scopeLevel==='organization'?'organizationBranding':'facilityBranding')}</h2>
    <div className="commercial-grid">
      <label>{t('platformNameAr')}<input className="ui-input" name="platformNameAr" defaultValue={branding.platformNameAr} required/></label>
      <label>{t('platformNameEn')}<input className="ui-input" name="platformNameEn" defaultValue={branding.platformNameEn} required/></label>
      <label>{t('organizationNameAr')}<input className="ui-input" name="organizationNameAr" defaultValue={branding.organizationNameAr} required/></label>
      <label>{t('organizationNameEn')}<input className="ui-input" name="organizationNameEn" defaultValue={branding.organizationNameEn} required/></label>
      <label>{t('facilityNameAr')}<input className="ui-input" name="facilityNameAr" defaultValue={branding.facilityNameAr}/></label>
      <label>{t('facilityNameEn')}<input className="ui-input" name="facilityNameEn" defaultValue={branding.facilityNameEn}/></label>
      <label>{t('logoUrl')}<input className="ui-input" name="logoUrl" type="url" defaultValue={branding.logoUrl}/></label>
      <label>{t('faviconUrl')}<input className="ui-input" name="faviconUrl" type="url" defaultValue={branding.faviconUrl}/></label>
      <label>{t('primaryColor')}<input className="ui-input color-input" name="primaryColor" type="color" defaultValue={branding.primaryColor}/></label>
      <label>{t('accentColor')}<input className="ui-input color-input" name="accentColor" type="color" defaultValue={branding.accentColor}/></label>
      <label>{t('contactEmail')}<input className="ui-input" name="contactEmail" type="email" defaultValue={branding.contactEmail}/></label>
      <label>{t('developerAttribution')}<select name="showDeveloperAttribution" defaultValue={branding.showDeveloperAttribution?'true':'false'}><option value="true">{t('show')}</option>{whiteLabelEnabled?<option value="false">{t('hide')}</option>:null}</select></label>
      <label>{t('reportHeaderAr')}<textarea className="ui-input" name="reportHeaderAr" defaultValue={branding.reportHeaderAr}/></label>
      <label>{t('reportHeaderEn')}<textarea className="ui-input" name="reportHeaderEn" defaultValue={branding.reportHeaderEn}/></label>
      <label>{t('reportFooterAr')}<textarea className="ui-input" name="reportFooterAr" defaultValue={branding.reportFooterAr}/></label>
      <label>{t('reportFooterEn')}<textarea className="ui-input" name="reportFooterEn" defaultValue={branding.reportFooterEn}/></label>
      <label>{t('emailSenderNameAr')}<input className="ui-input" name="emailSenderNameAr" defaultValue={branding.emailSenderNameAr}/></label>
      <label>{t('emailSenderNameEn')}<input className="ui-input" name="emailSenderNameEn" defaultValue={branding.emailSenderNameEn}/></label>
    </div>
    {!whiteLabelEnabled?<p className="commercial-note">{t('whiteLabelRequired')}</p>:null}
    {state?.status&&state.status!=='idle'?<p role="status" className="commercial-status">{t(`action.${state.status}`)}</p>:null}
    <button className="ui-button" type="submit" disabled={pending}>{pending?t('saving'):t('saveBranding')}</button>
  </form>;
}
