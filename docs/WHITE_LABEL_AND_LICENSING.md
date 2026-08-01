# White Label, deployment editions, and subscriptions

## Outcome

The platform supports two independent server-side commercial controls:

1. **Deployment edition:** defines what this deployed copy can contain.
2. **Scoped subscription:** defines what the current tenant, organization, or facility is entitled to use now.

In strict mode, effective module access is their intersection. Authentication,
RBAC, scope checks, and RLS remain mandatory after licensing succeeds.

## Ready deployment editions

Safe presets live in [`deployments/`](../deployments/README.md):

| Profile | Included modules |
| --- | --- |
| `full` | All registered modules |
| `inventory` | Core, Inventory & Custody, Audit |
| `quality` | Core, Inspections, Policies, CAPA, Reporting, Audit |
| `medication-safety` | Core, Medication Errors, CAPA, Reporting, Audit |
| `custom` | Core plus the explicit `PLATFORM_DEPLOYMENT_MODULES` allowlist |

These profiles support one shared SaaS deployment, a separate customer
deployment, private cloud, or on-premises packaging. They do not fork business
logic or create customer-specific source branches.

## Subscription model

`commercial_licenses` supports monthly, annual, perpetual, enterprise, and trial
licenses; cloud, private-cloud, and on-premises hosting; start, expiry, grace
period, user/facility limits, White Label entitlement, revision control, and an
external billing reference. `license_entitlements` enables modules independently.

Only a trusted service-role integration may provision or transition licenses.
Normal authenticated users have no direct commercial writes. Use the controlled
functions from an approved server job or billing adapter:

```sql
select public.provision_commercial_license(
  target_tenant := '<tenant-uuid>',
  target_organization := null,
  target_facility := null,
  requested_model := 'annual',
  requested_status := 'active',
  requested_hosting := 'cloud',
  requested_starts_at := now(),
  requested_expires_at := now() + interval '1 year',
  requested_grace_ends_at := now() + interval '1 year 14 days',
  requested_white_label := true,
  requested_modules := array['inventory','inspections','policies','capa','reporting','audit'],
  requested_max_users := 100,
  requested_max_facilities := 5,
  requested_external_reference := '<billing-system-reference>'
);
```

Never run provisioning from a browser or expose the service-role key. The
external reference is an idempotency key for billing integration: an exact
retry returns the existing license, while the same reference with different
scope, terms, limits, or modules fails closed. It must not contain a payment
credential or secret.

Suspend, expire, cancel, or reactivate with an optimistic revision:

```sql
select public.transition_commercial_license(
  target_license := '<license-uuid>',
  requested_status := 'suspended',
  requested_expires_at := '<existing-expiry>',
  requested_grace_ends_at := '<existing-grace-end>',
  expected_revision := 1
);
```

Provisioning and status transitions append audit events. Payment collection,
invoicing, tax, refunds, and provider webhooks are deliberately outside this
foundation and require a separate reviewed billing integration.

## Branding hierarchy

Effective signed-in branding merges safe values in this order:

1. repository defaults;
2. deployment environment fallback;
3. verified hostname branding;
4. tenant branding;
5. organization branding;
6. facility branding.

Supported values include Arabic and English platform, organization, facility,
branch, report, and email sender names; HTTPS logo/favicon URLs; primary/accent
colors; contact email; and developer-attribution visibility. Unknown keys,
non-HTTPS asset URLs, malformed colors, invalid email addresses, and oversized
values are rejected by both the application and database.

The Settings page exposes organization or facility branding only when the
current user holds `platform.manage_branding` for that exact scope. Updates use
revision conflict detection and write an audit event. Hiding the developer
attribution through database branding requires an active scoped White Label
entitlement.

## Login and custom domains

`branding_domains` stores an exact normalized hostname and a public-safe branding
subset. Direct anonymous reads are prohibited; `resolve_public_branding(host)`
returns only the safe JSON for an active, verified hostname. Domain ownership
verification is an operator responsibility: do not set `verified_at` until DNS
or another approved ownership check has completed.

For a dedicated customer deployment, environment branding works before login
without a domain database mapping. For shared SaaS custom domains, provision the
verified mapping through a trusted operator path.

## Enforcement and backward compatibility

- Default: `PLATFORM_LICENSE_ENFORCEMENT=disabled`. Existing deployments keep
  their current module access, restricted only by the deployment profile and
  normal authorization.
- Strict: `PLATFORM_LICENSE_ENFORCEMENT=strict`. A missing, suspended, cancelled,
  or expired-outside-grace license exposes Core only and module layouts redirect
  server-side to the unauthorized page.
- A deployment profile can only remove modules; a subscription cannot enable a
  module excluded from that deployed copy.

To roll back commercial enforcement without altering data, set enforcement to
`disabled` and redeploy. The migration is additive; retain license and branding
history for audit. Any later schema removal requires a separate reviewed
migration and retention decision.

## Acceptance requirements

- Test full and focused deployment profiles in both languages and directions.
- Test active, trial, grace, suspended, expired, and missing licenses.
- Test tenant, organization, and facility inheritance.
- Test that a module hidden from navigation is also denied by its server layout.
- Test cross-tenant license and branding denial.
- Test revision conflicts and White Label attribution enforcement.
- Never test with real customer names, credentials, payments, or health data.
