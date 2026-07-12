# PROJECT_BIBLE.md

# Healthcare Operations Platform
# منصة عمليات الرعاية الصحية

## 1. Purpose

This document is the permanent source of truth for the entire project.

Codex and any future developer must read this file before making any change.

The platform is a commercial, modular, bilingual healthcare operations platform designed for:

- Pharmacy operations.
- Quality management.
- Patient safety.
- Department inspections.
- Policies and procedures.
- Employee management.
- Reporting and analytics.
- Cloud and on-premises deployment.
- Standalone module sales.
- Subscription and perpetual licensing.

The system must support growth without forcing a complete rewrite.

---

## 2. Core Development Rule

Before implementing any task:

1. Read this file completely.
2. Read all related files in `docs/`.
3. Analyze the existing implementation.
4. Identify affected modules.
5. Preserve existing working functionality.
6. Document risks.
7. Avoid unnecessary rewrites.
8. Use migrations for database changes.
9. Do not touch production data directly.
10. Explain the testing plan.

After implementing any task:

1. Summarize what changed.
2. List all modified files.
3. Explain database changes.
4. Explain risks.
5. Provide test steps.
6. Confirm whether backward compatibility was preserved.
7. Update relevant documentation.
8. Update the changelog when applicable.

---

## 3. Primary Languages

The platform must fully support:

- Arabic.
- English.

Arabic is the primary interface language by default.

English must be a complete secondary interface language, not just translated labels.

The user must be able to switch languages at any time.

The selected language must be saved per user.

### Interface Direction

- Arabic: RTL.
- English: LTR.

### Localization Requirements

All screens, forms, alerts, validation messages, dashboards, tables, exports, and reports must support both languages.

Do not hardcode interface text inside components.

Use a centralized localization system suitable for Next.js, such as `next-intl`.

Suggested structure:

```text
locales/
  ar.json
  en.json
```

A feature is not complete if visible interface text exists in only one language.

---

## 4. Content Language Is Independent from Interface Language

Changing the interface language must not alter the original content.

Examples:

- The user may use an Arabic interface while reading an English policy.
- A medication error may be written in English while the interface is Arabic.
- An inspection template may be Arabic-only, English-only, or bilingual.
- Reports may be generated in Arabic, English, or bilingual format.

Do not automatically translate user-entered clinical or professional text without explicit approval.

---

## 5. Typography

Use the Thmanyah font for Arabic whenever technically and legally possible.

Use a visually compatible professional English font.

Provide safe fallback fonts.

Do not commit font files to the repository unless their license explicitly allows redistribution.

---

## 6. Technology Stack

Preferred stack:

- Next.js.
- TypeScript.
- PostgreSQL.
- Supabase as the primary recommended backend.
- Vercel for cloud deployment.
- GitHub for version control.
- PWA support for future mobile use.

The architecture must remain adaptable for:

- Firebase integration or migration.
- Private cloud.
- Internal hospital server.
- Local network deployment.
- On-premises deployment.
- Future mobile application conversion.

---

## 7. Architecture

Use a modular architecture.

Recommended approach:

- Modular Monolith initially.
- Clear internal boundaries.
- Shared services only when truly shared.
- Independent deployment capability later if needed.

Each module must:

- Have independent business logic.
- Have independent permissions.
- Have independent documentation.
- Have independent data ownership rules.
- Be enabled or disabled.
- Be extractable and sold separately.
- Support its own database if required.
- Avoid unnecessary dependency on other modules.

Shared code belongs in reusable packages only when at least two modules need it.

Suggested repository structure:

```text
apps/
services/
packages/
infrastructure/
tests/
docs/
legacy/
```

---

## 8. Existing Legacy Applications

The current legacy applications are:

1. Pharmacy Trolley.
2. Floor Stock.
3. Employee Management.

They must be preserved as working reference implementations.

Do not delete or rewrite legacy applications before:

- Documenting all current features.
- Documenting all current fields.
- Documenting all current database access.
- Creating acceptance tests.
- Creating a migration plan.
- Taking backups.

Legacy migration must be gradual.

---

## 9. User Interface Standards

All interfaces must support:

- Arabic and English.
- RTL and LTR.
- Light mode.
- Dark mode.
- Desktop.
- Tablet.
- Mobile.
- Accessibility.
- Keyboard navigation.
- Responsive design.
- Clear error messages.
- Loading states.
- Empty states.
- Confirmation dialogs for destructive actions.

Use consistent reusable components.

---

## 10. Search, Sorting, and Filtering

Every data list or table must support appropriate combinations of:

- Search.
- Alphabetical sorting.
- Date sorting.
- Status sorting.
- Department sorting.
- Category sorting.
- Priority sorting.
- Multi-column sorting.
- Saved filters.
- Reset filters.
- Pagination.
- Column visibility.
- Export of filtered results.

Sorting and searching must work correctly for Arabic and English content.

---

## 11. Import and Export

Every relevant module must support:

### Export

- CSV.
- Excel.
- JSON.
- PDF where appropriate.

### Import

- CSV.
- Excel.
- JSON.

### Import Modes

- Append.
- Merge.
- Update existing records.
- Full replacement.

Full replacement must require:

- Explicit confirmation.
- Backup creation.
- Permission check.
- Import validation.
- Error report.
- Audit log entry.

---

## 12. Automatic Saving

Use automatic saving where appropriate.

The interface must display:

- Saving.
- Saved.
- Last saved time.
- Unsaved changes.
- Save failed.
- Retry.

Auto-save must not overwrite conflicting changes silently.

Use conflict detection where needed.

---

## 13. Authentication and Application Lock

Do not use hardcoded passwords.

Do not store plain-text passwords.

Use secure authentication and server-side authorization.

The system must support:

- Manual lock.
- Automatic lock after inactivity.
- Configurable re-authentication interval.
- Default re-authentication suggestion: 15 minutes.
- Password change.
- Session expiration.
- Device/session management.
- MFA support where appropriate.

Sensitive operations must require server-side permission checks.

---

## 14. Security

Security is mandatory.

Never expose:

- Service role keys.
- Private API keys.
- Database passwords.
- Admin secrets.
- Tokens.
- Master passwords.

Use:

- Environment variables.
- Secret managers.
- Server-side authorization.
- Least privilege.
- Input validation.
- Output encoding.
- Rate limiting.
- Secure file upload validation.
- Signed or temporary file URLs.
- CSRF protection where applicable.
- XSS protection.
- SQL injection protection.
- Audit logging.
- Backup and recovery.
- Secure session handling.
- Role-based access control.

Do not claim that public client-side code can be made impossible to copy.

Protect commercial value by keeping sensitive business logic and licensing logic on the server.

---

## 15. Database Rules

Preferred database:

- PostgreSQL through Supabase.

The design must support future migration from or to Firebase.

Use a data access layer to reduce vendor lock-in.

All database changes must be managed by migrations.

Never:

- Rename or delete production columns casually.
- Change production data directly.
- Run destructive migration without backup.
- Store secrets in database scripts.
- Store passwords in plain text.

Support full Unicode.

Support Arabic and English search and sorting.

---

## 16. Audit Log and Last 24 Hours

The platform must include a unified page:

- آخر التغييرات خلال 24 ساعة
- Changes in the Last 24 Hours

It must show:

- User.
- Date and time.
- Module.
- Record.
- Action.
- Previous value when allowed.
- New value when allowed.
- Device or session information where appropriate.
- Safe undo capability when technically possible.

Undo must not bypass approval, compliance, or permission rules.

Approved, signed, published, or legally sensitive records must not be silently rolled back.

The audit log must not be editable by normal users.

---

## 17. Branding

Default developer attribution:

- تطوير: علي أبودهش
- Developed by Ali Abudahash

This must be stored centrally.

Do not hardcode it separately in every page.

Support per organization:

- Organization logo.
- Organization name.
- Facility name.
- Branch name.
- Contact details.
- Report header.
- Report footer.
- Login screen branding.
- Print branding.
- Email branding.
- White-label behavior.

Developer attribution visibility may depend on license level.

---

## 18. Licensing and Commercial Models

Every module must support future commercial licensing.

Supported models:

- Monthly subscription.
- Annual subscription.
- Perpetual license.
- Enterprise license.
- Trial license.
- Module-based license.
- User-based license.
- Facility-based license.
- On-premises license.
- Cloud-hosted license.

The licensing system must support:

- Expiration date.
- Grace period.
- Feature entitlements.
- Module activation.
- Tenant activation.
- License verification.
- Offline/on-premises scenarios.
- White label.
- Audit trail.

Licensing logic must be server-side.

---

## 19. Multi-Tenant and Standalone Support

The platform must support:

- One organization.
- Multiple organizations.
- Multiple branches.
- Shared database with tenant isolation.
- Separate database per customer.
- Separate deployment per customer.
- Standalone module deployment.

Tenant isolation must be enforced server-side.

---

## 20. Roles and Permissions

Use role-based access control.

Potential roles include:

- System Administrator.
- Organization Administrator.
- Facility Administrator.
- Department Manager.
- Pharmacy Manager.
- Quality Manager.
- Patient Safety Officer.
- Policy Administrator.
- Reviewer.
- Approver.
- Auditor.
- Employee.
- Read-Only User.

Permissions must control:

- View.
- Create.
- Edit.
- Delete.
- Review.
- Approve.
- Publish.
- Archive.
- Restore.
- Export.
- Import.
- Print.
- Download.
- Assign.
- Comment.
- View confidential records.
- Manage users.
- Manage roles.
- View audit logs.

Never rely only on hidden buttons.

---

## 21. Reporting

Reports must support:

- Arabic.
- English.
- Bilingual.

Reports should support:

- PDF.
- Excel.
- CSV.
- JSON where appropriate.

Report elements must support localization:

- Titles.
- Field labels.
- Tables.
- Charts.
- Dates.
- Headers.
- Footers.
- Signatures.
- Organization branding.
- Developer attribution.

---

# MODULE REQUIREMENTS

## 22. Pharmacy Trolley

The Pharmacy Trolley module must preserve and document all legacy features before migration.

It must eventually support:

- Medication storage locations.
- Drawers.
- Medication quantities.
- Expiry dates.
- Batch numbers.
- Hazardous medications.
- LASA medications.
- High-alert medications.
- Out-of-stock status.
- Search.
- Sorting.
- Filtering.
- Import.
- Export.
- Backup.
- Restore.
- Activity history.
- Configurable permissions.
- Arabic and English.
- Standalone deployment.

---

## 23. Floor Stock

The Floor Stock module must support:

- Departments.
- Department users.
- Pharmacy users.
- Department-specific medication lists.
- Requests.
- Dispensing.
- Limits.
- Monthly limits.
- Minimum and maximum quantities.
- Batch and expiry tracking.
- Notes.
- Reports.
- Import and export.
- Arabic and English.
- Standalone deployment.

---

## 24. Employee Management

The Employee Management module must support:

- Employee records.
- Identity information.
- Contact details.
- Job information.
- Licenses.
- Certifications.
- BLS/ACLS/PALS where applicable.
- Expiry alerts.
- Schedules.
- Shifts.
- Leave balances.
- Reports.
- Permissions.
- Arabic and English.
- Confidentiality controls.
- Standalone deployment.

---

## 25. Medication Errors

The Medication Errors module must include:

- Unique incident number.
- Facility.
- Department.
- Location.
- Date and time.
- Optional or anonymized patient data.
- Medication details.
- Strength.
- Dosage form.
- Route.
- Stage of medication-use process.
- Error type.
- Incident description.
- Whether the error reached the patient.
- Severity.
- Harm classification.
- Immediate action.
- Contributing factors.
- Root cause analysis.
- Corrective action.
- Preventive action.
- Assigned reviewer.
- Attachments.
- Approval.
- Closure.
- Reopening.
- Full audit trail.
- Confidential or anonymous reporter option.

Suggested workflow:

```text
New
Assigned
Under Investigation
Root Cause Analysis
Corrective Actions
Feedback to Reporter
Verification
Closed
Reopened
```

---

## 26. Medication Error Feedback

Feedback is a full workflow, not a single text box.

Support:

- Pharmacy feedback.
- Nursing feedback.
- Physician feedback.
- Quality feedback.
- Patient safety feedback.
- Management feedback.
- Public feedback.
- Confidential feedback.
- Request for more information.
- Attachments.
- Corrective action feedback.
- Preventive action feedback.
- RCA feedback.
- Lessons learned.
- Final recommendations.
- Approval comments.
- Rejection comments.
- Feedback status.
- Notification to reporter where allowed.
- Lock after case closure.
- Permission-based visibility.
- Export with incident report.

---

## 27. Medication Error Reports

Support:

- Monthly trends.
- Department trends.
- Medication trends.
- Stage of process.
- Error type.
- Reached-patient cases.
- Severity.
- Harm.
- Repeated causes.
- CAPA follow-up.
- Open cases.
- Overdue cases.
- Period comparison.
- Custom dashboards.
- Arabic reports.
- English reports.
- Bilingual reports.
- De-identification.

---

## 28. Drug Recalls

Support:

- Recall number.
- Medication.
- Manufacturer.
- Supplier.
- Batch or lot number.
- Expiry date.
- Recall reason.
- Recall classification.
- Announcement date.
- Affected locations.
- Available quantity.
- Located quantity.
- Quarantined quantity.
- Returned quantity.
- Destroyed quantity.
- Department acknowledgment.
- Notifications.
- Reminders.
- Attachments.
- Closure report.
- Future integration with Pharmacy Trolley and Floor Stock.

---

## 29. Crash Cart Inspections

Support:

- Facility.
- Department.
- Location.
- Cart identifier.
- Inspection date and time.
- Inspector.
- Seal or lock number.
- Seal status.
- Configurable checklist.
- Medication quantities.
- Equipment quantities.
- Expiry dates.
- Missing items.
- Damaged items.
- Expired items.
- Near-expiry items.
- Defibrillator checks.
- Oxygen checks.
- Battery checks.
- Pad checks.
- Notes.
- Corrective actions.
- Signatures.
- Photos.
- Inspection history.
- Missed-inspection alerts.
- Daily, weekly, and monthly reports.

---

## 30. Department Inspections

The Department Inspections module must be configurable and template-based.

Support:

- Different templates per department.
- Different templates per facility.
- Different templates per inspection type.
- Arabic-only templates.
- English-only templates.
- Bilingual templates.
- Yes/No.
- Compliant/Non-compliant.
- Score.
- Percentage.
- Rating from 1 to 5.
- Multiple choice.
- Text.
- Photo.
- Attachment.
- Signature.
- QR code.
- Critical questions.
- Weighted questions.
- Section weights.
- Required evidence.
- Per-question notes.
- Assigned corrective owner.
- Due date.
- Severity.
- Automatic CAPA creation.
- Automatic task creation.
- Follow-up inspection.
- Comparison across departments.
- Comparison across periods.
- Trend reports.
- Department ranking.
- Configurable scoring rules.
- Migration of existing Google Forms into internal templates.

---

## 31. Policies and Procedures

Support:

- Policies.
- Procedures.
- Guidelines.
- Protocols.
- SOPs.
- Work instructions.
- Forms.
- Checklists.
- Manuals.

Each record should support:

- Policy number.
- Arabic title.
- English title.
- Department.
- Category.
- Owner.
- Author.
- Reviewer.
- Approver.
- Version.
- Effective date.
- Review date.
- Expiry date.
- Status.
- Keywords.
- Tags.
- Attachments.
- Previous versions.
- Change summary.
- Reason for update.
- Required acknowledgment.

Support document languages:

- Arabic only.
- English only.
- Bilingual in one file.
- Separate Arabic and English linked versions.

Support:

- Original language.
- Translation status.
- Translation reviewer.
- Translation approval.
- Linked translation.
- Translation update date.

Workflow:

```text
Draft
Under Review
Pending Approval
Approved
Published
Scheduled Review
Superseded
Archived
```

Support:

- Reminders.
- Version history.
- Comparison.
- Restore previous version.
- Staff acknowledgment.
- Department assignment.
- Job-title assignment.
- QR code.
- Favorites.
- Recent documents.
- Search by Arabic and English.
- Search by policy number.
- Feedback.
- Clarification requests.
- Approval history.
- Audit trail.
- Confidentiality levels.

Policies may remain English-only when required by the organization.

---

## 32. CAPA

CAPA must be reusable across:

- Medication errors.
- Drug recalls.
- Inspections.
- Crash cart findings.
- Policy reviews.
- Audits.
- Quality events.

Support:

- Source.
- Finding.
- Root cause.
- Corrective action.
- Preventive action.
- Owner.
- Due date.
- Evidence.
- Verification.
- Effectiveness review.
- Closure.
- Reopening.
- Overdue alerts.
- Reports.
- Audit trail.

---

## 33. Dashboards

Support role-based dashboards for:

- Pharmacy Manager.
- Quality Manager.
- Patient Safety Officer.
- Nursing Manager.
- Department Manager.
- Hospital Director.
- System Administrator.

Dashboards must be configurable and bilingual.

---

## 34. Notifications

Support:

- In-app notifications.
- Email notifications.
- Optional SMS or other channels later.
- Reminder schedules.
- Escalation.
- Read/unread status.
- Per-user preferences.
- Per-role preferences.
- Per-module preferences.

---

## 35. File Storage

Support:

- PDF.
- Word.
- Excel.
- PowerPoint.
- Images.
- Approved file types.

Requirements:

- Secure upload.
- File validation.
- File size limits.
- Virus/malware scanning where possible.
- Private storage.
- Signed URLs.
- Versioning.
- Audit log.
- Access control.

---

## 36. Testing

Every module must include:

- Unit tests.
- Integration tests.
- Permission tests.
- Localization tests.
- RTL/LTR tests.
- Import/export tests.
- Migration tests.
- Security tests.
- Acceptance tests.
- Regression tests.

No major feature is complete without tests.

---

## 37. Documentation

Every module must include:

- Purpose.
- Users.
- Screens.
- Workflows.
- Data model.
- Permissions.
- Reports.
- Import/export.
- Audit behavior.
- Security considerations.
- Acceptance criteria.
- Standalone deployment notes.
- Commercial licensing notes.

---

## 38. Git Rules

Use focused commits.

Do not mix unrelated changes.

Recommended branch types:

```text
main
develop
feature/*
fix/*
docs/*
security/*
```

Commit messages should be clear.

Examples:

```text
docs: add medication error requirements
feat: add inspection template builder
fix: correct tenant permission check
security: enforce server-side policy access
```

---

## 39. Final Rule

Do not optimize for short-term convenience.

Always optimize for:

- Maintainability.
- Security.
- Modularity.
- Commercial readiness.
- Bilingual support.
- Mobile readiness.
- Safe data handling.
- Future standalone sales.
- Long-term scalability.

When instructions conflict, prioritize:

1. Security.
2. Data integrity.
3. Existing working functionality.
4. Legal and compliance obligations.
5. Maintainability.
6. User experience.
7. Speed of implementation.
