# Inventory & Custody Core — Phase One

Phase One provides the reusable, tenant-scoped inventory foundation. Transfers
and reservations were added in Phase Two. An authenticated bilingual read-only
web foundation now exposes RLS-authorized locations and positive balance
projections; it does not implement custody, reconciliation, wastage, imports,
CAPA adapters, or inventory write actions.

## Data model

- `catalog_items` and `catalog_item_identifiers` hold shared identities,
  including authoritative NUPCO and MOH identifiers.
- `inventory_item_profiles` activates a catalog item at a facility and records
  the facility operational controlled classification.
- `inventory_units` are reusable; `inventory_item_units` supplies conversions
  and exactly one active base unit per profile.
- `inventory_locations` is the single scoped hierarchy. Protected transit is
  reserved for trusted future transfer setup.
- `inventory_batches` records lot and expiry completeness. Lot/expiry edits
  require controlled functions; a split preserves parent/child lineage.
- `inventory_commands`, `inventory_transactions`, `inventory_ledger_entries`,
  and `inventory_balance_projections` form the append-only posting path.

## Posting and security

Opening and migration commands are idempotent by requester, scope,
`idempotency_key`, and `request_hash`. A reused key with a different hash is
rejected. Every posted transaction balances per item profile, batch, recording
channel, and active base item-unit. Physical entries update a read-only
projection; external-control entries balance the transaction but never enter
physical stock balances. Negative physical balances are rejected.

Direct INSERT, UPDATE and DELETE are revoked from client roles for protected
domain tables. Authenticated clients use narrowly scoped functions; RLS uses
the established membership and permission helpers. Internal posting, event and
audit helpers are not executable by client roles. Each successful posting adds
an inventory event and the shared `audit_events` record in the same database
transaction.

## Deferred work

Custody assignment and handover, controlled-drug segregation workflows,
imports, reconciliation, operational adjustments, wastage, CAPA adapters,
notifications, printing, reporting, and all inventory write UI remain deferred.
The implemented read-only UI uses the current Supabase user session, explicit
server-side scope/permission preflight, and existing RLS policies; it never uses
the service role. Hash chaining is also deferred: without external anchoring it
would be only an integrity indicator, not a complete tamper-proof guarantee.
