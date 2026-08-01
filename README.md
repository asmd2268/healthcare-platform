# Healthcare Platform

This repository contains the shared foundation and the first operational module foundations for a commercial, modular healthcare operations platform. The shared Next.js core lives in `apps/web`; Inventory & Custody Core now includes an authenticated, RLS-protected read-only interface for locations, balances, transfers, and transfer detail.

## Current status

The Core Platform Foundation is implemented: bilingual shell, initial design system, secure configuration boundaries, and shared contracts. A secure development-ready Supabase/PostgreSQL foundation adds versioned migrations, Supabase Auth session checks, RLS contracts, platform roles, administration persistence schema, audit-event storage, and fictional local seeds. The commercial foundation now adds server-enforced deployment editions, scoped module subscriptions, and inherited White Label branding without weakening authentication, permissions, or RLS. Notifications, file upload, workflow execution, permanent deletion, audit undo, and payment-provider integration remain explicit non-production placeholders. The permanent requirements remain in [PROJECT_BIBLE.md](PROJECT_BIBLE.md).

## Repository map

See [the project structure guide](docs/PROJECT_STRUCTURE.md) for ownership and intended use of each top-level directory.

Sellable full-platform and focused-module presets live in [`deployments/`](deployments/README.md). See [White Label, deployment editions, and subscriptions](docs/WHITE_LABEL_AND_LICENSING.md) for enforcement, provisioning, branding inheritance, and rollout rules.

## Source of truth

Read [PROJECT_BIBLE.md](PROJECT_BIBLE.md) completely before changing this repository. It governs architecture, safety, modularity, localization, legacy preservation, testing, and commercial readiness.

## Before implementation begins

Confirm the initial product scope, target users, data classification, hosting requirements, and applicable regulatory obligations. The initial architecture and delivery plan should then be recorded in the documentation before feature code is added.

## Local development

See [local development](docs/LOCAL_DEVELOPMENT.md), [environment variables](docs/ENVIRONMENT_VARIABLES.md), [core platform](docs/CORE_PLATFORM.md), [testing](docs/TESTING.md), and [threat model](docs/THREAT_MODEL.md).

For local Supabase, run the supported CLI workflow only against a disposable environment: `supabase start`, then `supabase db reset`. This applies migrations and the fictional seed data. See [authentication](docs/AUTHENTICATION.md), [RLS](docs/ROW_LEVEL_SECURITY.md), [multi-tenancy](docs/MULTI_TENANCY.md), and [Platform Owner bootstrap](docs/PLATFORM_OWNER_BOOTSTRAP.md). Never use `db reset` or seed data against production.

The shared [Workflow Engine](docs/WORKFLOW_ENGINE.md) establishes reusable versions, transitions, tasks, approvals, comments, events, and SLA/reminder contracts. Module adapters are intentionally limited until each module adopts the engine without weakening existing safeguards.

The shared Reporting and Analytics Engine provides versioned report/dashboard contracts, scoped RLS schema, bilingual administration placeholders, and reusable widget components. It does not replace existing module dashboards or execute production report queries yet.

## Inventory & Custody Core

The inventory ledger, balance projection, facility-transfer lifecycle, reservation accounting, deterministic locking, and reservation-expiry worker are implemented in PostgreSQL. The web application now provides a bilingual read-only inventory foundation using the signed-in Supabase session and database RLS; it does not expose create, issue, receive, reject, return, dispose, cancel, or remainder-closing actions. Notifications, printing, reporting, import/export, custody workflows, and operational write UI remain deferred. See [Phase One](docs/modules/inventory-custody-core-phase-one.md) and [Phase Two](docs/modules/inventory-transfers-phase-two.md).

## Department Inspections foundation

The first business-module foundation provides configurable bilingual templates, scoring contracts, draft inspection UI, findings, and demonstration reports through a local repository abstraction. Persistence, evidence uploads, PDF/Excel exports, CAPA creation, and production authorization remain explicit placeholders. See the [module documentation](docs/modules/department-inspections.md).

## Platform Administration UI

Administration screens use demonstration repository data and local-only draft interactions. Backend persistence, real authorization, imports, exports, and deletion execution remain placeholders. See [Platform Administration UI](docs/PLATFORM_ADMINISTRATION_UI.md).

Staging SQL validation: `SUPABASE_ENV=staging DATABASE_URL=<secret> npm run test:sql:staging`. It never resets a remote database and refuses production-looking targets.

These are fictional-data security smoke tests, not complete RLS certification. Every executable SQL file must contain its own real `BEGIN` and `ROLLBACK`; the runner only preflights that convention and is not a full SQL parser.
