# Inventory & Custody Core — Phase Two: facility transfers

Phase Two adds facility-local stock transfers on top of the Phase One ledger. It does not introduce a second balance or idempotency model.

## Boundaries

- A transfer is tenant-, organization-, and facility-scoped. Cross-facility and cross-organization transfers are rejected.
- Every transfer has a source, a receiving root, and one protected facility transit location. A receipt can use the receiving root or one of its descendants only, and the receiver must manage that location.
- Each planned allocation is exact: source location, profile, batch, recording channel, available disposition, and base quantity.
- A physical operation is one allocation and one physical grain. Multi-batch or multi-destination requests create multiple immutable operation rows under one idempotent command.

## Truth and lifecycle

`inventory_transfer_allocations` holds only draft plans. `inventory_transfer_operations`, immutable `inventory_reservation_adjustments`, ledger entries, and read-only summary projections are the execution truth. `inventory_reservation_events` is retained only as deprecated historical evidence and is no longer an accounting source.

Reservation remaining is derived as `reservation.quantity - sum(reservation adjustments)`. Each posted issue writes an `issue_consumed` adjustment; cancellation writes `manually_released`; allocation-linked remainder closure writes `closure_released`; trusted expiry processing writes `expiry_released`. These rows and reservations are append-only. ATP is physical `available` stock less active, unexpired reservation remaining.

### Reservation-expiry worker

`expire_inventory_transfer_reservations(p_actor uuid, p_limit integer default 100)` is a `service_role`-only, bounded database worker. `p_actor` is now a strict-cutover automation principal: it must be an active `automation_identities` registration for the sole supported purpose, `inventory.reservation_expiry`, and its tenant/organization/facility scope must permit every selected transfer. It is not an arbitrary human UUID with an inventory permission. The worker rejects null or out-of-range limits (`1`–`1000`), selects candidates deterministically by expiry timestamp and reservation ID with `FOR UPDATE SKIP LOCKED`, then acquires the transfer execution graph locks and recomputes the remaining quantity.

For each still-expired positive remainder, it uses the stable `reservation-expiry:<reservation-id>` command key and an append-only `expiry_released` adjustment for the exact remaining quantity. Replays therefore create no second adjustment, transfer event, or audit event. Commands, adjustments, transfer events, and shared audit events attribute the automation principal, while any future on-behalf-of workflow must record a separately validated human initiator rather than replacing that actor. Expiry materialization is non-physical: it creates no inventory transaction, ledger entry, or balance-projection movement. ATP already excludes expired reservations by timestamp, so materializing the adjustment preserves ATP while making the expired reservation's derived remaining quantity zero. `SKIP LOCKED` is only worker scheduling; deterministic graph locks and post-lock revalidation protect races with issue, cancellation, remainder closure, and other expiry workers.

Automation Auth users are provisioned outside migrations without credentials in repository SQL. The registry prevents active automation principals from holding ordinary memberships or active role assignments; registration and deactivation are trusted, audited lifecycle operations. Existing schedulers that supplied a human actor must provision and register a dedicated non-interactive principal before this strict-cutover migration is deployed.

The controlled transfer status is refreshed from operations; clients cannot alter it. The lifecycle is `draft → reserved → partially_issued|issued → receiving → completed`; cancellation is possible only before issue. `close_inventory_transfer_remainder` explicitly closes unissued demand and releases its reservation. Rejected stock moves from transit to `returns_hold`, then only `return` or `dispose_rejected` can consume it.

## Posting

- Issue: source `available -Q`, protected transit `transit +Q`.
- Receive: protected transit `transit -Q`, approved destination disposition `+Q`.
- Reject: protected transit `transit -Q`, same transit `returns_hold +Q`.
- Return: protected transit `returns_hold -Q`, source `available +Q`.
- Final rejected disposition: protected transit `returns_hold -Q`, approved controlled destination disposition `+Q`.

All postings use the Phase One balanced transaction and ledger helpers, update the projection under its advisory lock, emit an inventory event, transfer event, and shared audit event atomically.

## Security and concurrency

Only controlled `SECURITY DEFINER` functions are executable by authenticated users; tables are read-only under RLS. Transfer actions use `inventory_commands` first: same idempotency key and hash replay the completed result; a changed hash fails. The implementation locks transfer/allocation/reservation rows and takes deterministic advisory locks for physical grains before revalidation and posting. Posted operations, reservation adjustments, destinations, historical reservation events, and transfer events are append-only.

Closing post-issue demand requires the dedicated `inventory.transfer.close_remainder` permission; `inventory.transfer.cancel` does not grant closure authority.

## Deferred

Cross-facility transfers, supplier receipt/procurement, custody, controlled wastage approval, attachments/imports, CAPA adapters, UI, notifications, printing, and reporting remain out of scope. Legacy reservation-event backfill, standalone manual release, and correction/reversal adjustments remain deferred.
