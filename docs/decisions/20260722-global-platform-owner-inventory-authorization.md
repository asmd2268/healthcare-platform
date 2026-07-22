# Decision: global Platform Owner in trusted inventory authorization

## Status

Accepted for implementation and review on 2026-07-22.

## Context

`bootstrap_first_platform_owner` intentionally creates one global `platform_owner` assignment with null tenant, organization, and facility scope and no tenant membership. The shared platform authorization contract treats that exact assignment as cross-tenant. `inventory_actor_has_permission` nevertheless required every actor to have an active matching membership, so a correctly bootstrapped Platform Owner could not register or deactivate an automation identity for a tenant.

## Decision

Trusted inventory authorization recognizes an active assignment as membership-independent only when all of the following are true:

- the role key is exactly `platform_owner`;
- the role scope level is exactly `global`;
- tenant, organization, and facility on the assignment are all null; and
- the role still grants the requested permission or `platform.full_access`.

Every other role continues to require an active membership matching the target tenant and optional organization and facility, plus a compatible role assignment and permission.

## Consequences

A bootstrapped global Platform Owner can administer automation identities across tenants as already documented. Tenant-, organization-, and facility-scoped administrators are unchanged. A role merely labelled global cannot bypass membership. The change is additive, requires no data backfill, preserves direct-table and RPC grants, and is reversible only through a later reviewed migration that restores the previous function definition.
