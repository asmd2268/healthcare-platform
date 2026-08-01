# Decision: server-side commercial packaging and white-label inheritance

## Context

The repository had central default branding and JSON branding storage, but the
runtime always rendered fixed demo values. Licensing existed only as permissions
and documentation. A client-side module menu or build-time flag alone would not
provide commercial enforcement and could not support shared SaaS, dedicated
deployments, or standalone module sales safely.

## Decision

- Keep one codebase and represent sellable copies as deployment profiles.
- Represent customer purchases as scoped, time-bound licenses with module
  entitlements and optional White Label rights.
- Calculate effective modules as deployment/profile intersection on the server.
- Gate each licensed route family in a server layout; navigation filtering is
  presentation only.
- Resolve signed-in branding by tenant → organization → facility inheritance.
- Resolve pre-authentication custom-domain branding through an exact verified
  hostname function that returns public-safe JSON only.
- Keep license provisioning and domain verification service-role-only. Customer
  branding updates use a narrow permission-checked RPC with revision and audit.
- Leave enforcement disabled by default for backward compatibility.

## Consequences

The platform can be deployed as full, focused, or custom editions without source
forks. Subscriptions can expire or be suspended without trusting the browser.
Existing installations remain operational until strict enforcement is enabled.
Billing-provider integration, DNS ownership automation, secure logo upload, and
formatted email/report renderers remain separate integrations; this foundation
defines their trusted contracts without embedding provider-specific logic.
