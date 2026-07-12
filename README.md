# Healthcare Platform

This repository is the foundation for a commercial, modular healthcare operations platform. The shared Next.js core now lives in `apps/web`; no healthcare business module has been implemented.

## Current status

The Core Platform Foundation is implemented: bilingual shell, initial design system, secure configuration boundaries, and shared contracts. The permanent requirements remain in [PROJECT_BIBLE.md](PROJECT_BIBLE.md).

## Repository map

See [the project structure guide](docs/PROJECT_STRUCTURE.md) for ownership and intended use of each top-level directory.

## Source of truth

Read [PROJECT_BIBLE.md](PROJECT_BIBLE.md) completely before changing this repository. It governs architecture, safety, modularity, localization, legacy preservation, testing, and commercial readiness.

## Before implementation begins

Confirm the initial product scope, target users, data classification, hosting requirements, and applicable regulatory obligations. The initial architecture and delivery plan should then be recorded in the documentation before feature code is added.

## Local development

See [local development](docs/LOCAL_DEVELOPMENT.md), [environment variables](docs/ENVIRONMENT_VARIABLES.md), [core platform](docs/CORE_PLATFORM.md), [testing](docs/TESTING.md), and [threat model](docs/THREAT_MODEL.md).
