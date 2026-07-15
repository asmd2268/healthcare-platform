# CAPA security controls

Migration `202607150001_secure_capa_lifecycle_and_children.sql` is additive and
preserves existing CAPA records. It replaces unsafe callable implementations with
controlled functions, closes the assignment schema-drift gap, and does not depend
on Reporting for transactional audit logging.

## Lifecycle

`draft → submitted → under_review → approved → in_progress → pending_evidence`
is normally followed by `pending_effectiveness_review`. A return from
`pending_evidence → in_progress` is allowed only to an authorized evidence handler,
with a required reason and an existing quarantined/failed evidence result.
`in_progress → pending_effectiveness_review → effective` is the successful path.
An ineffective or reopen decision atomically records the effectiveness review and
sets the CAPA to `reopened`; there is no usable intermediate `ineffective` state.
Only `effective → completed → closed → archived`, `submitted|under_review → rejected → archived`,
and `approved → cancelled → archived` are terminal paths. Reasons are required for
reject, cancel, and reopen. Submission, approval, evidence, RCA, effectiveness,
extension, and closure predicates are checked on the server before transition.

## Evidence and audit

CAPA evidence uses the same trusted-upload contract as Policies: private storage,
short-lived authorization, strict path, checksum verification, malware acceptance,
and a service-role-only finalizer. A browser cannot finalize metadata, make the
bucket public, or directly write CAPA evidence/event rows. Signed download URLs
must be issued by the server only after `can_view_capa`; storage read policy remains
private and verifies the CAPA relationship. Expired, unfinalized authorizations
are immediately inaccessible; the trusted storage worker obtains their keys from
`list_expired_capa_upload_keys()` and removes orphaned objects. The upload UI must
remain disabled until that trusted worker and signed-download endpoint are deployed.

The CAPA event writer records both `capa_events` and the shared `audit_events`
ledger through a CAPA-only trusted path. It deliberately does not call Reporting.

## Operational verification

Run `npm run check` for the web suite and `npm run test:sql:staging` only against a
disposable staging database with the required staging variables. The executable
SQL test `002_capa_security.executable.sql` asserts function grants, no direct CAPA
write policies, private evidence storage, audit independence, and fail-closed
lifecycle behavior.

## Verification status

- TypeScript checks: passed.
- Vitest: 84 passed.
- SQL syntax/static checks: passed.
- Disposable database migration reset: passed locally through `202607150002`.
- Executable SQL catalogue/grant/policy tests: passed locally (3 files).
- Behavioral RLS tests: not run.
- JWT identity-isolation tests: not run.
- Concurrency numbering test: not run.
- Trusted Storage policies: not exercised against a real local Supabase stack.

The current SQL file is a catalogue/grant/policy suite with one fail-closed
function invocation; it is not a complete behavioral RLS, lifecycle, or
concurrency suite. Evidence Upload must remain unavailable in the interface until
a trusted server endpoint issues upload authorizations and signed download URLs.
