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

`expire_inventory_transfer_reservations(p_actor uuid, p_limit integer default 100)` is a `service_role`-only, bounded database worker. `p_actor` is now a strict-cutover automation principal: it must be an active `automation_identities` registration for the sole supported purpose, `inventory.reservation_expiry`, and its tenant/organization/facility scope must permit every selected transfer. It is not an arbitrary human UUID with an inventory permission. The worker rejects null or out-of-range limits (`1`–`1000`), selects candidates deterministically by expiry timestamp and reservation ID, locks each transfer with `FOR UPDATE SKIP LOCKED` for worker scheduling, then acquires the transfer execution graph locks and recomputes the remaining quantity.

For each still-expired positive remainder, it uses the stable `reservation-expiry:<reservation-id>` command key and an append-only `expiry_released` adjustment for the exact remaining quantity. Replays therefore create no second adjustment, transfer event, or audit event. Commands, adjustments, transfer events, and shared audit events attribute the automation principal, while any future on-behalf-of workflow must record a separately validated human initiator rather than replacing that actor. Expiry materialization is non-physical: it creates no inventory transaction, ledger entry, or balance-projection movement. ATP already excludes expired reservations by timestamp, so materializing the adjustment preserves ATP while making the expired reservation's derived remaining quantity zero. `SKIP LOCKED` is only worker scheduling; deterministic graph locks and post-lock revalidation protect races with issue, cancellation, remainder closure, and other expiry workers.

Automation Auth users are provisioned outside migrations without credentials in repository SQL. The registry prevents active automation principals from holding ordinary memberships or active role assignments; registration and deactivation are trusted, audited lifecycle operations. Existing schedulers that supplied a human actor must provision and register a dedicated non-interactive principal before this strict-cutover migration is deployed.

The human administrator used for registration or deactivation must hold `platform.manage_roles` for the requested scope. A true global `platform_owner` assignment (global role with all assignment scope columns null) satisfies this check across tenants without a membership, matching the platform authorization contract. No other global-looking role receives that bypass; all other administrators still require an active matching membership and scoped role permission.

### Scheduler cutover

The implemented scheduler boundary is the server-only Next.js route `GET /api/internal/inventory/reservation-expiry`. `apps/web/vercel.json` schedules it daily at `02:00 UTC`; deployments needing a different approved cadence may use an equivalent scheduler, but must call the same route with `Authorization: Bearer <CRON_SECRET>`. The route takes no actor parameter. It reads only the deployment-secret `INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID`, drains up to `INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES` bounded RPC batches, and returns only aggregate counts and a `drainLimitReached` signal—never identity, scope, database, or credential details on failure.

Vercel Cron invokes only production deployments and does not automatically retry failed runs. A manually repeated delivery is safe because the database worker uses stable reservation command keys and append-only adjustment constraints; it cannot create duplicate expiry effects. Monitor a non-2xx response as a failed operational job, correct the provisioning/configuration problem, then retry deliberately. The route itself is provider-neutral for internal/on-prem deployments; the caller must keep the same server-only secret boundary and never obtain the service-role key.

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
