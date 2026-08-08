# Deployment editions

These presets contain safe, non-secret commercial configuration only. Copy the
selected file's values into the deployment environment, then provide the normal
Supabase URL and anon key through the secret manager. Never commit populated
credentials.

Available editions:

- `full.env.example`: every platform module included by the deployment.
- `inventory.env.example`: Inventory & Custody plus Core and Audit.
- `quality.env.example`: Inspections, Policies, CAPA, Reporting, Core, and Audit.
- `medication-safety.env.example`: Medication Errors, CAPA, Reporting, Core, and Audit.
- `custom-white-label.env.example`: explicit module allowlist and deployment-level branding.

`PLATFORM_LICENSE_ENFORCEMENT=disabled` is backward-compatible packaging: the
deployment profile alone determines available modules. Set it to `strict` only
after an active database license and entitlements have been provisioned. In
strict mode, effective access is the intersection of deployment modules and the
active scoped subscription; Core remains available to permit sign-in and safe
settings access.

Deployment profiles are not an authorization substitute. Every enabled module
continues to enforce authentication, tenant scope, permissions, and RLS.
