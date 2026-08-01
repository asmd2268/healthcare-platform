import {getTranslations} from 'next-intl/server';
import {canPlatformPermission} from '@/lib/auth.server';
import {loadBrandingEditorContext,loadPlatformExperience} from '@/lib/commercial.server';
import {BrandingForm} from '@/components/commercial/branding-form';

export default async function SettingsPage(){
  const t=await getTranslations('commercial');const experience=await loadPlatformExperience();
  const canManageOrganization=experience.scope?.organizationId?await canPlatformPermission('platform.manage_branding',{...experience.scope,facilityId:null}):false;
  const canManageFacility=experience.scope?.organizationId&&experience.scope.facilityId?await canPlatformPermission('platform.manage_branding',experience.scope):false;
  const organizationEditor=experience.scope?.organizationId&&canManageOrganization?await loadBrandingEditorContext(experience.scope,'organization'):null;
  const facilityEditor=experience.scope?.organizationId&&experience.scope.facilityId&&canManageFacility?await loadBrandingEditorContext(experience.scope,'facility'):null;
  const summary=experience.commercialSummary;
  return <section className="page commercial-page"><p className="eyebrow">{t('eyebrow')}</p><h1>{t('title')}</h1><p>{t('body')}</p>
    <div className="commercial-summary">
      <article className="ui-card"><h2>{t('deployment')}</h2><dl><dt>{t('profile')}</dt><dd>{t(`profiles.${experience.deploymentProfile}`)}</dd><dt>{t('enforcement')}</dt><dd>{t(`enforcementModes.${experience.licenseEnforcement}`)}</dd></dl></article>
      <article className="ui-card"><h2>{t('subscription')}</h2>{summary?<dl><dt>{t('model')}</dt><dd>{t(`models.${summary.licenseModel}`)}</dd><dt>{t('status')}</dt><dd>{t(`statuses.${summary.status}`)}</dd><dt>{t('hosting')}</dt><dd>{t(`hostingModes.${summary.hostingMode}`)}</dd><dt>{t('expires')}</dt><dd>{summary.expiresAt?new Intl.DateTimeFormat(t('dateLocale')).format(new Date(summary.expiresAt)):t('never')}</dd></dl>:<p>{t('noActiveLicense')}</p>}</article>
    </div>
    <article className="ui-card"><h2>{t('enabledModules')}</h2><div className="module-chips">{experience.enabledModules.map((module)=><span className="ui-badge" key={module}>{t(`modules.${module}`)}</span>)}</div></article>
    {organizationEditor||facilityEditor?<div className="commercial-branding">{organizationEditor?<BrandingForm scopeLevel="organization" revision={organizationEditor.record?.revision??null} branding={organizationEditor.branding} whiteLabelEnabled={organizationEditor.whiteLabelEnabled}/>:null}{facilityEditor?<BrandingForm scopeLevel="facility" revision={facilityEditor.record?.revision??null} branding={facilityEditor.branding} whiteLabelEnabled={facilityEditor.whiteLabelEnabled}/>:null}</div>:<p className="commercial-note">{t('brandingReadOnly')}</p>}
  </section>;
}
