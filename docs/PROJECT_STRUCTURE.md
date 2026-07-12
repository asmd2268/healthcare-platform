# Project structure

The layout below separates deployable products, reusable code, operational infrastructure, and documentation while keeping the repository implementation-neutral.

| Path | Intended contents | Current state |
| --- | --- | --- |
| `apps/` | User-facing applications, such as patient, clinician, or administrator experiences. | Empty |
| `services/` | Independently deployable backend services and integration adapters. | Empty |
| `packages/` | Shared libraries, types, design system components, and utilities. | Empty |
| `infrastructure/` | Infrastructure definitions, deployment configuration, and environment documentation. | Empty |
| `tests/` | Cross-application test fixtures, end-to-end tests, and quality documentation. | Empty |
| `legacy/` | Preserved working reference implementations for Pharmacy Trolley, Floor Stock, and Employee Management. | Reserved; no legacy code has been added to this repository. |
| `docs/` | Product, architecture, security, and development documentation. | Initialized |

## Conventions

- Add application code only after the initial scope and architecture have been approved.
- Keep each deployable application or service isolated in its own direct child directory.
- Place reusable implementation only in `packages/`; do not create a shared package until at least two consumers exist.
- Record significant technical and security decisions in `docs/architecture/` before or alongside implementation.
- Do not place production health information, credentials, or environment secrets in this repository.
- Preserve legacy applications and migrate them gradually only after feature/field/data-access documentation, acceptance tests, a migration plan, and backups exist.
- Treat `PROJECT_BIBLE.md` as the permanent source of truth; this guide is subordinate to it.
