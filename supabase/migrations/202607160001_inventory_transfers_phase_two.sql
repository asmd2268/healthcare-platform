-- Inventory & Custody Core — Phase Two: facility-local stock transfers.
-- This migration deliberately reuses the Phase One command, transaction,
-- ledger, projection and audit path.  Transfer execution is append-only.

-- Correct the Phase One projection writer before transfer operations depend on
-- it.  `FOUND` must be captured immediately after the lookup: invoking
-- set_config() itself sets FOUND and otherwise turns a missing projection row
-- into a no-op instead of inserting the initial physical balance.
create or replace function public.inventory_apply_projection(p_entry public.inventory_ledger_entries) returns void language plpgsql security definer set search_path=public as $$
declare q numeric(20,6); projection_exists boolean; begin
 if p_entry.account_type<>'physical' then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',p_entry.location_id::text,p_entry.inventory_item_profile_id::text,coalesce(p_entry.batch_id::text,'∅'),p_entry.recording_channel::text,p_entry.disposition::text),0));
 select bp.quantity_base into q from public.inventory_balance_projections bp where bp.location_id=p_entry.location_id and bp.inventory_item_profile_id=p_entry.inventory_item_profile_id and bp.batch_id is not distinct from p_entry.batch_id and bp.recording_channel=p_entry.recording_channel and bp.disposition=p_entry.disposition for update;
 projection_exists:=found;
 perform set_config('app.inventory_projection_controlled','on',true);
 if projection_exists then
  q:=q+p_entry.quantity_base;
  if q<0 then raise exception 'Inventory posting would create negative physical balance' using errcode='23514'; end if;
  update public.inventory_balance_projections bp set quantity_base=q,updated_at=now() where bp.location_id=p_entry.location_id and bp.inventory_item_profile_id=p_entry.inventory_item_profile_id and bp.batch_id is not distinct from p_entry.batch_id and bp.recording_channel=p_entry.recording_channel and bp.disposition=p_entry.disposition;
 else
  if p_entry.quantity_base<0 then raise exception 'Inventory posting would create negative physical balance' using errcode='23514'; end if;
  insert into public.inventory_balance_projections(tenant_id,organization_id,facility_id,location_id,inventory_item_profile_id,batch_id,recording_channel,disposition,quantity_base) select ip.tenant_id,ip.organization_id,ip.facility_id,p_entry.location_id,p_entry.inventory_item_profile_id,p_entry.batch_id,p_entry.recording_channel,p_entry.disposition,p_entry.quantity_base from public.inventory_item_profiles ip where ip.id=p_entry.inventory_item_profile_id;
 end if;
end $$;

do $$ begin create type public.inventory_transfer_status as enum
 ('draft','reserved','partially_issued','issued','receiving','completed','cancelled','closed_remainder'); exception when duplicate_object then null; end $$;
do $$ begin create type public.inventory_transfer_operation_type as enum
 ('reservation_released','reservation_expired','issue','receive','reject','return','dispose_rejected','cancel','close_remainder'); exception when duplicate_object then null; end $$;

alter table public.inventory_commands drop constraint if exists inventory_commands_command_type_check;
alter table public.inventory_commands add constraint inventory_commands_command_type_check check(command_type in
 ('opening','migration','reversal','batch_split','batch_attribute','transfer_create','transfer_reserve','transfer_issue','transfer_receive','transfer_reject','transfer_return','transfer_dispose_rejected','transfer_cancel','transfer_close_remainder'));

insert into public.permissions(key,name_ar,name_en) values
 ('inventory.transfer.view','عرض التحويلات','View inventory transfers'),
 ('inventory.transfer.create','إنشاء تحويل مخزون','Create inventory transfers'),
 ('inventory.transfer.reserve','حجز مخزون للتحويل','Reserve transfer stock'),
 ('inventory.transfer.issue','صرف تحويل مخزون','Issue transfer stock'),
 ('inventory.transfer.receive','استلام تحويل مخزون','Receive transfer stock'),
 ('inventory.transfer.reject','رفض تحويل مخزون','Reject transfer stock'),
 ('inventory.transfer.return','إرجاع تحويل مرفوض','Return rejected transfer stock'),
 ('inventory.transfer.dispose','تحديد مصير تحويل مرفوض','Dispose rejected transfer stock'),
 ('inventory.transfer.cancel','إلغاء تحويل مخزون','Cancel inventory transfer'),
 ('inventory.transfer.close_remainder','إغلاق المتبقي غير المصروف','Close unissued transfer remainder')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.key like 'inventory.transfer.%'
where r.key='platform_owner' on conflict do nothing;

create table public.inventory_transfers (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id), organization_id uuid not null references public.organizations(id), facility_id uuid not null references public.facilities(id),
 source_location_id uuid not null references public.inventory_locations(id) on delete restrict,
 destination_root_location_id uuid not null references public.inventory_locations(id) on delete restrict,
 transit_location_id uuid not null references public.inventory_locations(id) on delete restrict,
 status public.inventory_transfer_status not null default 'draft',
 created_by uuid not null references public.user_profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), updated_by uuid not null references public.user_profiles(id),
 check(source_location_id<>destination_root_location_id), check(source_location_id<>transit_location_id), check(destination_root_location_id<>transit_location_id)
);
create table public.inventory_transfer_lines (
 id uuid primary key default gen_random_uuid(), transfer_id uuid not null references public.inventory_transfers(id) on delete restrict,
 inventory_item_profile_id uuid not null references public.inventory_item_profiles(id) on delete restrict,
 requested_quantity_base numeric(20,6) not null check(requested_quantity_base>0),
 created_at timestamptz not null default now(), created_by uuid not null references public.user_profiles(id),
 unique(transfer_id,inventory_item_profile_id)
);
-- Allocations are an editable plan only while the transfer is draft.  Execution
-- quantities are never stored here; they are derived from operation records.
create table public.inventory_transfer_allocations (
 id uuid primary key default gen_random_uuid(), transfer_line_id uuid not null references public.inventory_transfer_lines(id) on delete restrict,
 source_location_id uuid not null references public.inventory_locations(id) on delete restrict,
 batch_id uuid not null references public.inventory_batches(id) on delete restrict,
 recording_channel public.inventory_recording_channel not null,
 source_disposition public.inventory_stock_disposition not null default 'available' check(source_disposition='available'),
 planned_quantity_base numeric(20,6) not null check(planned_quantity_base>0),
 created_at timestamptz not null default now(), created_by uuid not null references public.user_profiles(id),
 unique(transfer_line_id,source_location_id,batch_id,recording_channel,source_disposition)
);
create table public.inventory_reservations (
 id uuid primary key default gen_random_uuid(), transfer_allocation_id uuid not null unique references public.inventory_transfer_allocations(id) on delete restrict,
 quantity_base numeric(20,6) not null check(quantity_base>0), expires_at timestamptz not null,
 created_at timestamptz not null default now(), created_by uuid not null references public.user_profiles(id),
 check(expires_at>created_at)
);
create table public.inventory_reservation_events (
 id uuid primary key default gen_random_uuid(), reservation_id uuid not null references public.inventory_reservations(id) on delete restrict,
 operation_type public.inventory_transfer_operation_type not null check(operation_type in ('reservation_released','reservation_expired')),
 quantity_base numeric(20,6) not null check(quantity_base>0), reason text not null,
 created_at timestamptz not null default now(), created_by uuid not null references public.user_profiles(id)
);
create table public.inventory_transfer_operations (
 id uuid primary key default gen_random_uuid(), transfer_id uuid not null references public.inventory_transfers(id) on delete restrict,
 transfer_allocation_id uuid references public.inventory_transfer_allocations(id) on delete restrict,
 command_id uuid not null references public.inventory_commands(id) on delete restrict,
 transaction_id uuid references public.inventory_transactions(id) on delete restrict,
 operation_type public.inventory_transfer_operation_type not null,
 inventory_item_profile_id uuid references public.inventory_item_profiles(id) on delete restrict,
 batch_id uuid references public.inventory_batches(id) on delete restrict,
 recording_channel public.inventory_recording_channel,
 source_location_id uuid references public.inventory_locations(id) on delete restrict,
 destination_location_id uuid references public.inventory_locations(id) on delete restrict,
 source_disposition public.inventory_stock_disposition,
 destination_disposition public.inventory_stock_disposition,
 quantity_base numeric(20,6) check(quantity_base>0), reason text,
 created_at timestamptz not null default now(), created_by uuid not null references public.user_profiles(id),
 check((operation_type in ('issue','receive','reject','return','dispose_rejected') and transfer_allocation_id is not null and transaction_id is not null and inventory_item_profile_id is not null and batch_id is not null and recording_channel is not null and source_location_id is not null and destination_location_id is not null and source_disposition is not null and destination_disposition is not null and quantity_base is not null)
       or (operation_type in ('cancel','close_remainder') and transfer_allocation_id is null and transaction_id is null and quantity_base is null)),
 unique(command_id,transfer_allocation_id,operation_type,destination_location_id)
);
-- One receipt operation is one physical grain.  The child table makes the
-- destination quantity explicit and is guarded against divergence.
create table public.inventory_transfer_receipt_destinations (
 id uuid primary key default gen_random_uuid(), operation_id uuid not null unique references public.inventory_transfer_operations(id) on delete restrict,
 destination_location_id uuid not null references public.inventory_locations(id) on delete restrict,
 inventory_item_profile_id uuid not null references public.inventory_item_profiles(id), batch_id uuid not null references public.inventory_batches(id),
 recording_channel public.inventory_recording_channel not null, quantity_base numeric(20,6) not null check(quantity_base>0), created_at timestamptz not null default now()
);
create table public.inventory_transfer_events (
 id uuid primary key default gen_random_uuid(), transfer_id uuid not null references public.inventory_transfers(id) on delete restrict,
 command_id uuid references public.inventory_commands(id) on delete restrict, operation_id uuid references public.inventory_transfer_operations(id) on delete restrict,
 actor_id uuid not null references public.user_profiles(id), action text not null, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(),
 check(not (metadata ?| array['password','token','secret','access_token']))
);

-- Exact, append-only closure of demand that will not be issued.  A closure is
-- either allocation-linked or line-unallocated; it can never be both.
create table public.inventory_transfer_remainder_closures (
 id uuid primary key default gen_random_uuid(), transfer_id uuid not null references public.inventory_transfers(id) on delete restrict,
 transfer_line_id uuid not null references public.inventory_transfer_lines(id) on delete restrict,
 transfer_allocation_id uuid references public.inventory_transfer_allocations(id) on delete restrict,
 inventory_item_profile_id uuid not null references public.inventory_item_profiles(id) on delete restrict,
 reservation_id uuid references public.inventory_reservations(id) on delete restrict,
 quantity_base numeric(20,6) not null check(quantity_base>0), command_id uuid not null references public.inventory_commands(id) on delete restrict,
 reason text not null check(nullif(trim(reason),'') is not null), metadata jsonb not null default '{}'::jsonb,
 created_by uuid not null references public.user_profiles(id), created_at timestamptz not null default now(),
 check(not (metadata ?| array['password','token','secret','access_token'])),
 check((transfer_allocation_id is not null) or reservation_id is null),
 unique nulls not distinct(command_id,transfer_line_id,transfer_allocation_id)
);

create or replace function public.enforce_inventory_transfer_remainder_closure() returns trigger language plpgsql security definer set search_path=public as $$
declare line_row public.inventory_transfer_lines%rowtype; allocation_row public.inventory_transfer_allocations%rowtype; begin
 select l.* into line_row from public.inventory_transfer_lines l where l.id=new.transfer_line_id;
 if not found or line_row.transfer_id<>new.transfer_id or line_row.inventory_item_profile_id<>new.inventory_item_profile_id then raise exception 'Transfer remainder closure line integrity denied' using errcode='23503'; end if;
 if new.transfer_allocation_id is not null then select a.* into allocation_row from public.inventory_transfer_allocations a where a.id=new.transfer_allocation_id; if not found or allocation_row.transfer_line_id<>new.transfer_line_id then raise exception 'Transfer remainder closure allocation integrity denied' using errcode='23503'; end if; if new.reservation_id is not null and not exists(select 1 from public.inventory_reservations r where r.id=new.reservation_id and r.transfer_allocation_id=new.transfer_allocation_id) then raise exception 'Transfer remainder closure reservation integrity denied' using errcode='23503'; end if; end if; return new; end $$;
create trigger inventory_transfer_remainder_closure_integrity before insert on public.inventory_transfer_remainder_closures for each row execute function public.enforce_inventory_transfer_remainder_closure();
create or replace function public.prevent_inventory_transfer_remainder_closure_mutation() returns trigger language plpgsql security definer set search_path=public as $$ begin raise exception 'Posted inventory transfer records are append-only' using errcode='42501'; end $$;
create trigger inventory_transfer_remainder_closure_immutable before update or delete on public.inventory_transfer_remainder_closures for each row execute function public.prevent_inventory_transfer_remainder_closure_mutation();

create or replace view public.inventory_transfer_summary_projection as
select l.id as transfer_line_id,l.transfer_id,l.inventory_item_profile_id,l.requested_quantity_base,
 coalesce(a.planned_quantity_base,0) as planned_quantity_base,
 coalesce(x.issued,0) as issued_quantity_base,coalesce(x.received,0) as received_quantity_base,
 coalesce(x.rejected,0) as rejected_quantity_base,coalesce(x.returned,0) as returned_quantity_base,
 coalesce(x.disposed,0) as disposed_quantity_base,
 coalesce(c.allocation_closed,0) as allocation_closed_quantity_base,
 coalesce(c.line_unallocated_closed,0) as line_unallocated_closed_quantity_base,
 coalesce(c.closed_quantity,0) as closed_remainder_quantity_base,
 greatest(0,coalesce(x.issued,0)-coalesce(x.received,0)-coalesce(x.rejected,0)) as transit_quantity_base,
 greatest(0,coalesce(x.rejected,0)-coalesce(x.returned,0)-coalesce(x.disposed,0)) as returns_hold_quantity_base,
 greatest(0,l.requested_quantity_base-coalesce(x.issued,0)-coalesce(c.closed_quantity,0)) as unissued_quantity_base
from public.inventory_transfer_lines l
left join lateral (select sum(planned_quantity_base) planned_quantity_base from public.inventory_transfer_allocations a where a.transfer_line_id=l.id) a on true
left join lateral (select sum(quantity_base) filter(where operation_type='issue') issued,sum(quantity_base) filter(where operation_type='receive') received,sum(quantity_base) filter(where operation_type='reject') rejected,sum(quantity_base) filter(where operation_type='return') returned,sum(quantity_base) filter(where operation_type='dispose_rejected') disposed from public.inventory_transfer_operations o where o.transfer_id=l.transfer_id and o.inventory_item_profile_id=l.inventory_item_profile_id) x on true
left join lateral (select sum(quantity_base) filter(where transfer_allocation_id is not null) allocation_closed,sum(quantity_base) filter(where transfer_allocation_id is null) line_unallocated_closed,sum(quantity_base) closed_quantity from public.inventory_transfer_remainder_closures c where c.transfer_line_id=l.id) c on true;

create or replace function public.can_view_inventory_transfer(p_transfer uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.inventory_transfers t where t.id=p_transfer and public.scope_allowed(t.tenant_id,t.organization_id,t.facility_id) and (public.has_platform_permission('inventory.transfer.view',t.tenant_id,t.organization_id,t.facility_id) or public.can_manage_inventory_location(t.source_location_id) or public.can_manage_inventory_location(t.destination_root_location_id) or public.has_platform_permission('platform.full_access',t.tenant_id,t.organization_id,t.facility_id))); $$;
create or replace function public.can_manage_inventory_transfer(p_transfer uuid,p_permission text) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.inventory_transfers t where t.id=p_transfer and public.scope_allowed(t.tenant_id,t.organization_id,t.facility_id) and (public.has_platform_permission(p_permission,t.tenant_id,t.organization_id,t.facility_id) or public.has_platform_permission('platform.full_access',t.tenant_id,t.organization_id,t.facility_id))); $$;
create or replace function public.inventory_transfer_location_allowed(p_root uuid,p_candidate uuid) returns boolean language sql stable security definer set search_path=public as $$
 with recursive tree as (select l.id,l.parent_location_id from public.inventory_locations l where l.id=p_candidate union all select p.id,p.parent_location_id from public.inventory_locations p join tree t on t.parent_location_id=p.id)
 select exists(select 1 from tree where id=p_root); $$;

create or replace function public.inventory_transfer_write_event(p_transfer uuid,p_command uuid,p_operation uuid,p_action text,p_metadata jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path=public as $$
declare t public.inventory_transfers%rowtype; begin select tr.* into t from public.inventory_transfers tr where tr.id=p_transfer; if not found or p_metadata ?| array['password','token','secret','access_token'] then raise exception 'Inventory transfer audit write denied'; end if;
 insert into public.inventory_transfer_events(transfer_id,command_id,operation_id,actor_id,action,metadata) values(t.id,p_command,p_operation,auth.uid(),p_action,p_metadata);
 insert into public.audit_events(tenant_id,organization_id,facility_id,actor_id,action,entity_type,entity_id,metadata) values(t.tenant_id,t.organization_id,t.facility_id,auth.uid(),p_action,'inventory_transfer',t.id,p_metadata); end $$;

-- Claim/replay happens before any business locks or posting.  A unique command
-- row serializes retries; a changed hash is always rejected.
create or replace function public.claim_inventory_transfer_command(p_transfer uuid,p_type public.inventory_transaction_type,p_key text,p_hash text,p_payload jsonb,p_reason text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare t public.inventory_transfers%rowtype; c public.inventory_commands%rowtype; begin
 select tr.* into t from public.inventory_transfers tr where tr.id=p_transfer; if not found or coalesce(trim(p_key),'')='' or length(coalesce(p_hash,''))<16 then raise exception 'Inventory transfer command denied'; end if;
 select ic.* into c from public.inventory_commands ic where ic.tenant_id=t.tenant_id and ic.organization_id=t.organization_id and ic.facility_id=t.facility_id and ic.requester_id=auth.uid() and ic.idempotency_key=trim(p_key) for update;
 if found then if c.request_hash<>p_hash then raise exception 'Inventory idempotency key was reused with a different request'; end if; return c.id; end if;
 begin insert into public.inventory_commands(tenant_id,organization_id,facility_id,command_type,status,requester_id,approver_id,idempotency_key,request_hash,payload,reason,submitted_at,approved_at) values(t.tenant_id,t.organization_id,t.facility_id,p_type,'approved',auth.uid(),auth.uid(),trim(p_key),p_hash,p_payload, nullif(trim(p_reason),''),now(),now()) returning id into c.id;
 exception when unique_violation then select ic.* into c from public.inventory_commands ic where ic.tenant_id=t.tenant_id and ic.organization_id=t.organization_id and ic.facility_id=t.facility_id and ic.requester_id=auth.uid() and ic.idempotency_key=trim(p_key) for update; if not found or c.request_hash<>p_hash then raise exception 'Inventory idempotency key was reused with a different request'; end if; end; return c.id; end $$;
create or replace function public.inventory_transfer_transit(p_t uuid,p_o uuid,p_f uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare x uuid; begin select l.id into x from public.inventory_locations l where l.tenant_id=p_t and l.organization_id=p_o and l.facility_id=p_f and l.protected_transit and l.active limit 1; if x is null then perform set_config('app.inventory_transit_setup','on',true); insert into public.inventory_locations(tenant_id,organization_id,facility_id,code,name_en,location_kind,protected_transit,created_by,updated_by) values(p_t,p_o,p_f,'__TRANSFER_TRANSIT__','Protected transfer transit','transit',true,auth.uid(),auth.uid()) returning id into x; end if; return x; end $$;

-- Phase One prevents direct protected-transit creation.  The only additional
-- path is the private, validated setup helper above; clients still cannot set
-- the transaction-local control value because they have no table INSERT grant.
create or replace function public.enforce_inventory_location_integrity() returns trigger language plpgsql security definer set search_path=public as $$
declare parent_row public.inventory_locations%rowtype; begin
 if not exists(select 1 from public.facilities f where f.id=new.facility_id and f.tenant_id=new.tenant_id and f.organization_id=new.organization_id) then raise exception 'Inventory location facility scope mismatch' using errcode='23503'; end if;
 if new.department_id is not null and not exists(select 1 from public.departments d where d.id=new.department_id and d.tenant_id=new.tenant_id and d.organization_id=new.organization_id and d.facility_id=new.facility_id) then raise exception 'Inventory location department scope mismatch' using errcode='23503'; end if;
 if new.parent_location_id is not null then select l.* into parent_row from public.inventory_locations l where l.id=new.parent_location_id; if not found or (parent_row.tenant_id,parent_row.organization_id,parent_row.facility_id) is distinct from (new.tenant_id,new.organization_id,new.facility_id) then raise exception 'Inventory location parent scope mismatch' using errcode='23503'; end if; if new.id=parent_row.id or exists(with recursive tree as (select l.id,l.parent_location_id from public.inventory_locations l where l.id=parent_row.id union all select c.id,c.parent_location_id from public.inventory_locations c join tree t on c.id=t.parent_location_id) select 1 from tree where id=new.id) then raise exception 'Inventory location hierarchy cycle' using errcode='23514'; end if; end if;
 if tg_op='UPDATE' and (old.parent_location_id is distinct from new.parent_location_id or old.tenant_id<>new.tenant_id or old.organization_id<>new.organization_id or old.facility_id<>new.facility_id or old.department_id is distinct from new.department_id or old.active<>new.active or (old.confidential and not new.confidential)) and (exists(select 1 from public.inventory_balance_projections p where p.location_id=old.id and p.quantity_base<>0) or exists(select 1 from public.inventory_ledger_entries e where e.location_id=old.id)) then raise exception 'Inventory location with ledger history cannot be structurally changed' using errcode='23514'; end if;
 if new.protected_transit and auth.role() not in ('service_role','postgres') and current_setting('app.inventory_transit_setup',true)<>'on' then raise exception 'Protected transit location requires trusted setup' using errcode='42501'; end if; return new; end $$;

create or replace function public.enforce_inventory_transfer_integrity() returns trigger language plpgsql security definer set search_path=public as $$
declare s public.inventory_locations%rowtype; d public.inventory_locations%rowtype; x public.inventory_locations%rowtype; begin
 select * into s from public.inventory_locations where id=new.source_location_id; select * into d from public.inventory_locations where id=new.destination_root_location_id; select * into x from public.inventory_locations where id=new.transit_location_id;
 if not found or (s.tenant_id,s.organization_id,s.facility_id) is distinct from (new.tenant_id,new.organization_id,new.facility_id) or (d.tenant_id,d.organization_id,d.facility_id) is distinct from (new.tenant_id,new.organization_id,new.facility_id) or (x.tenant_id,x.organization_id,x.facility_id) is distinct from (new.tenant_id,new.organization_id,new.facility_id) or not x.protected_transit then raise exception 'Inventory transfer location scope denied' using errcode='23503'; end if;
 if tg_op='UPDATE' and current_setting('app.inventory_transfer_controlled',true)<>'on' then raise exception 'Inventory transfer state requires a controlled function' using errcode='42501'; end if; return new; end $$;
create trigger inventory_transfer_integrity before insert or update on public.inventory_transfers for each row execute function public.enforce_inventory_transfer_integrity();
create or replace function public.prevent_inventory_transfer_immutable_mutation() returns trigger language plpgsql security definer set search_path=public as $$ begin raise exception 'Posted inventory transfer records are append-only' using errcode='42501'; end $$;
create trigger inventory_transfer_operations_immutable before update or delete on public.inventory_transfer_operations for each row execute function public.prevent_inventory_transfer_immutable_mutation();
create trigger inventory_transfer_events_immutable before update or delete on public.inventory_transfer_events for each row execute function public.prevent_inventory_transfer_immutable_mutation();
create trigger inventory_reservation_events_immutable before update or delete on public.inventory_reservation_events for each row execute function public.prevent_inventory_transfer_immutable_mutation();
create trigger inventory_receipt_destination_immutable before update or delete on public.inventory_transfer_receipt_destinations for each row execute function public.prevent_inventory_transfer_immutable_mutation();
create or replace function public.enforce_transfer_receipt_destination() returns trigger language plpgsql security definer set search_path=public as $$
declare o public.inventory_transfer_operations%rowtype; begin select op.* into o from public.inventory_transfer_operations op where op.id=new.operation_id; if not found or o.operation_type<>'receive' or (new.destination_location_id,new.inventory_item_profile_id,new.batch_id,new.recording_channel,new.quantity_base) is distinct from (o.destination_location_id,o.inventory_item_profile_id,o.batch_id,o.recording_channel,o.quantity_base) then raise exception 'Transfer receipt destination does not match receipt operation' using errcode='23514'; end if; return new; end $$;
create trigger transfer_receipt_destination_integrity before insert or update on public.inventory_transfer_receipt_destinations for each row execute function public.enforce_transfer_receipt_destination();

create or replace function public.inventory_transfer_reservation_remaining(p_reservation uuid) returns numeric language sql stable security definer set search_path=public as $$
 select greatest(0,r.quantity_base-coalesce((select sum(o.quantity_base) from public.inventory_transfer_operations o where o.transfer_allocation_id=r.transfer_allocation_id and o.operation_type='issue'),0)-coalesce((select sum(e.quantity_base) from public.inventory_reservation_events e where e.reservation_id=r.id),0)) from public.inventory_reservations r where r.id=p_reservation; $$;

create or replace view public.inventory_transfer_closure_summary as
select l.id as transfer_line_id,l.transfer_id,l.inventory_item_profile_id,
 coalesce(sum(c.quantity_base) filter(where c.transfer_allocation_id is not null),0) as allocation_closed_quantity_base,
 coalesce(sum(c.quantity_base) filter(where c.transfer_allocation_id is null),0) as line_unallocated_closed_quantity_base,
 coalesce(sum(c.quantity_base),0) as closed_quantity_base
from public.inventory_transfer_lines l left join public.inventory_transfer_remainder_closures c on c.transfer_line_id=l.id group by l.id,l.transfer_id,l.inventory_item_profile_id;
create or replace function public.inventory_transfer_refresh_status(p_transfer uuid) returns void language plpgsql security definer set search_path=public as $$
declare t public.inventory_transfers%rowtype; issued numeric:=0; received numeric:=0; rejected numeric:=0; returned_qty numeric:=0; disposed numeric:=0; closed_qty numeric:=0; requested_qty numeric:=0; target public.inventory_transfer_status; begin select * into t from public.inventory_transfers where id=p_transfer for update; select coalesce(sum(quantity_base) filter(where operation_type='issue'),0),coalesce(sum(quantity_base) filter(where operation_type='receive'),0),coalesce(sum(quantity_base) filter(where operation_type='reject'),0),coalesce(sum(quantity_base) filter(where operation_type='return'),0),coalesce(sum(quantity_base) filter(where operation_type='dispose_rejected'),0) into issued,received,rejected,returned_qty,disposed from public.inventory_transfer_operations where transfer_id=p_transfer; select coalesce(sum(requested_quantity_base),0) into requested_qty from public.inventory_transfer_lines where transfer_id=p_transfer; select coalesce(sum(quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures where transfer_id=p_transfer;
 if exists(select 1 from public.inventory_transfer_operations where transfer_id=p_transfer and operation_type='cancel') then target:='cancelled'; elsif issued=0 and exists(select 1 from public.inventory_reservations r join public.inventory_transfer_allocations a on a.id=r.transfer_allocation_id join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id=p_transfer and r.expires_at>now() and public.inventory_transfer_reservation_remaining(r.id)>0) then target:='reserved'; elsif issued=0 then target:='draft'; elsif received+returned_qty+disposed>=issued and issued+closed_qty>=requested_qty then target:='completed'; elsif issued<requested_qty-closed_qty then target:='partially_issued'; elsif received+rejected>0 then target:='receiving'; else target:='issued'; end if; perform set_config('app.inventory_transfer_controlled','on',true); update public.inventory_transfers set status=target,updated_at=now(),updated_by=auth.uid() where id=p_transfer; end $$;

-- Replacement: own the Phase One idempotency command before creating any
-- transfer-side effect.  A concurrent claimant waits on the unique command
-- row and replays its already-recorded aggregate id.
create or replace function public.create_inventory_transfer(p_t uuid,p_o uuid,p_f uuid,p_source uuid,p_destination uuid,p_allocations jsonb,p_key text,p_hash text,p_reason text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare new_transfer_id uuid:=gen_random_uuid(); command_row public.inventory_commands%rowtype; transit_id uuid; allocation jsonb; profile_row public.inventory_item_profiles%rowtype; line_id uuid; source_row public.inventory_locations%rowtype; destination_row public.inventory_locations%rowtype; begin
 if auth.uid() is null or coalesce(trim(p_key),'')='' or length(coalesce(p_hash,''))<16 or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 or not public.scope_allowed(p_t,p_o,p_f) or not public.has_platform_permission('inventory.transfer.create',p_t,p_o,p_f) then raise exception 'Inventory transfer creation denied'; end if;
 select ic.* into command_row from public.inventory_commands ic where ic.tenant_id=p_t and ic.organization_id=p_o and ic.facility_id=p_f and ic.requester_id=auth.uid() and ic.idempotency_key=trim(p_key) for update;
 if found then if command_row.request_hash<>p_hash then raise exception 'Inventory idempotency key was reused with a different request'; end if; return (command_row.payload->>'result_transfer_id')::uuid; end if;
 begin
  insert into public.inventory_commands(tenant_id,organization_id,facility_id,command_type,status,requester_id,approver_id,idempotency_key,request_hash,payload,reason,submitted_at,approved_at) values(p_t,p_o,p_f,'transfer_create','approved',auth.uid(),auth.uid(),trim(p_key),p_hash,jsonb_build_object('result_transfer_id',new_transfer_id,'allocations',p_allocations),nullif(trim(p_reason),''),now(),now()) returning * into command_row;
 exception when unique_violation then
  select ic.* into command_row from public.inventory_commands ic where ic.tenant_id=p_t and ic.organization_id=p_o and ic.facility_id=p_f and ic.requester_id=auth.uid() and ic.idempotency_key=trim(p_key) for update;
  if not found or command_row.request_hash<>p_hash then raise exception 'Inventory idempotency key was reused with a different request'; end if;
  return (command_row.payload->>'result_transfer_id')::uuid;
 end;
 select * into source_row from public.inventory_locations where id=p_source; select * into destination_row from public.inventory_locations where id=p_destination;
 if not found or not source_row.active or not destination_row.active or (source_row.tenant_id,source_row.organization_id,source_row.facility_id) is distinct from (p_t,p_o,p_f) or (destination_row.tenant_id,destination_row.organization_id,destination_row.facility_id) is distinct from (p_t,p_o,p_f) or not public.can_manage_inventory_location(p_source) or not public.can_manage_inventory_location(p_destination) then raise exception 'Inventory transfer creation denied'; end if;
 transit_id:=public.inventory_transfer_transit(p_t,p_o,p_f);
 insert into public.inventory_transfers(id,tenant_id,organization_id,facility_id,source_location_id,destination_root_location_id,transit_location_id,created_by,updated_by) values(new_transfer_id,p_t,p_o,p_f,p_source,p_destination,transit_id,auth.uid(),auth.uid());
 for allocation in select value from jsonb_array_elements(p_allocations) loop
  select * into profile_row from public.inventory_item_profiles ip where ip.id=(allocation->>'profile_id')::uuid;
  if not found or not profile_row.active or (profile_row.tenant_id,profile_row.organization_id,profile_row.facility_id) is distinct from (p_t,p_o,p_f) or not exists(select 1 from public.inventory_batches b where b.id=(allocation->>'batch_id')::uuid and b.inventory_item_profile_id=profile_row.id and b.active) or coalesce((allocation->>'quantity_base')::numeric,0)<=0 then raise exception 'Inventory transfer allocation denied'; end if;
  insert into public.inventory_transfer_lines(transfer_id,inventory_item_profile_id,requested_quantity_base,created_by) values(new_transfer_id,profile_row.id,(allocation->>'quantity_base')::numeric,auth.uid()) on conflict(transfer_id,inventory_item_profile_id) do update set requested_quantity_base=inventory_transfer_lines.requested_quantity_base+excluded.requested_quantity_base returning id into line_id;
  insert into public.inventory_transfer_allocations(transfer_line_id,source_location_id,batch_id,recording_channel,planned_quantity_base,created_by) values(line_id,p_source,(allocation->>'batch_id')::uuid,coalesce((allocation->>'channel')::public.inventory_recording_channel,'system'),(allocation->>'quantity_base')::numeric,auth.uid());
 end loop;
 update public.inventory_commands set status='posted',posted_at=now() where id=command_row.id;
 perform public.inventory_transfer_write_event(new_transfer_id,command_row.id,null,'inventory.transfer_created',jsonb_build_object('reason',nullif(trim(p_reason),'')));
 return new_transfer_id;
end $$;

-- Use non-conflicting PL/pgSQL variable names: a record variable named `a`
-- would otherwise shadow an SQL table alias during parsing.
create or replace function public.reserve_inventory_transfer(p_transfer uuid,p_expires_at timestamptz,p_key text,p_hash text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; allocation_row record; available_qty numeric; reserved_qty numeric; begin
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 if not found or transfer_row.status<>'draft' or p_expires_at<=now() or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.reserve') then raise exception 'Inventory transfer reservation denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,'transfer_reserve',p_key,p_hash,jsonb_build_object('transfer_id',p_transfer,'expires_at',p_expires_at),null);
 if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for allocation_row in select ia.*,il.inventory_item_profile_id from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where il.transfer_id=p_transfer order by ia.source_location_id,il.inventory_item_profile_id,ia.batch_id,ia.recording_channel for update loop
  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',allocation_row.source_location_id::text,allocation_row.inventory_item_profile_id::text,allocation_row.batch_id::text,allocation_row.recording_channel::text,'available'),0));
  select coalesce(bp.quantity_base,0) into available_qty from public.inventory_balance_projections bp where bp.location_id=allocation_row.source_location_id and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id and bp.batch_id=allocation_row.batch_id and bp.recording_channel=allocation_row.recording_channel and bp.disposition='available' for update;
  select coalesce(sum(public.inventory_transfer_reservation_remaining(ir.id)),0) into reserved_qty from public.inventory_reservations ir join public.inventory_transfer_allocations existing_allocation on existing_allocation.id=ir.transfer_allocation_id where existing_allocation.source_location_id=allocation_row.source_location_id and existing_allocation.batch_id=allocation_row.batch_id and existing_allocation.recording_channel=allocation_row.recording_channel and ir.expires_at>now();
  if available_qty-reserved_qty<allocation_row.planned_quantity_base then raise exception 'Inventory transfer reservation exceeds available-to-promise' using errcode='23514'; end if;
  insert into public.inventory_reservations(transfer_allocation_id,quantity_base,expires_at,created_by) values(allocation_row.id,allocation_row.planned_quantity_base,p_expires_at,auth.uid());
 end loop;
 update public.inventory_commands set status='posted',posted_at=now(),payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id;
 perform public.inventory_transfer_refresh_status(p_transfer); perform public.inventory_transfer_write_event(p_transfer,command_id,null,'inventory.transfer_reserved',jsonb_build_object('expires_at',p_expires_at)); return p_transfer;
end $$;

create or replace function public.issue_inventory_transfer(p_transfer uuid,p_issues jsonb,p_key text,p_hash text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; transaction_id uuid; item jsonb; allocation_row record; reservation_row public.inventory_reservations%rowtype; quantity numeric; line_existing_issued numeric; line_closed numeric; line_requested_now numeric; entries jsonb:='[]'::jsonb; operation_id uuid; base_unit_id uuid; begin
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 if not found or transfer_row.status not in ('reserved','partially_issued','issued') or jsonb_typeof(p_issues)<>'array' or jsonb_array_length(p_issues)=0 or coalesce(trim(p_reason),'')='' or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.issue') then raise exception 'Inventory transfer issue denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,'transfer_issue',p_key,p_hash,jsonb_build_object('issues',p_issues),p_reason); if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for item in select value from jsonb_array_elements(p_issues) loop
  select ia.*,il.inventory_item_profile_id,il.requested_quantity_base into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where ia.id=(item->>'transfer_allocation_id')::uuid and il.transfer_id=p_transfer for update;
  select * into reservation_row from public.inventory_reservations ir where ir.transfer_allocation_id=allocation_row.id for update; quantity:=(item->>'quantity_base')::numeric;
  if not found or quantity<=0 or reservation_row.expires_at<=now() or quantity>public.inventory_transfer_reservation_remaining(reservation_row.id) or quantity+coalesce((select sum(o.quantity_base) from public.inventory_transfer_operations o where o.transfer_allocation_id=allocation_row.id and o.operation_type='issue'),0)+coalesce((select sum(c.quantity_base) from public.inventory_transfer_remainder_closures c where c.transfer_allocation_id=allocation_row.id),0)>allocation_row.planned_quantity_base then raise exception 'Inventory transfer issue reservation denied'; end if;
  select coalesce(sum(o.quantity_base),0) into line_existing_issued from public.inventory_transfer_operations o join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id where a.transfer_line_id=allocation_row.transfer_line_id and o.operation_type='issue';
  select coalesce(sum(c.quantity_base),0) into line_closed from public.inventory_transfer_remainder_closures c where c.transfer_line_id=allocation_row.transfer_line_id;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_requested_now from jsonb_array_elements(p_issues) request_item join public.inventory_transfer_allocations request_allocation on request_allocation.id=(request_item.value->>'transfer_allocation_id')::uuid where request_allocation.transfer_line_id=allocation_row.transfer_line_id;
  if line_existing_issued+line_closed+line_requested_now>allocation_row.requested_quantity_base then raise exception 'Inventory transfer issue exceeds line requested quantity' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',allocation_row.source_location_id::text,allocation_row.inventory_item_profile_id::text,allocation_row.batch_id::text,allocation_row.recording_channel::text,'available'),0));
  if not exists(select 1 from public.inventory_balance_projections bp where bp.location_id=allocation_row.source_location_id and bp.inventory_item_profile_id=allocation_row.inventory_item_profile_id and bp.batch_id=allocation_row.batch_id and bp.recording_channel=allocation_row.recording_channel and bp.disposition='available' and bp.quantity_base>=quantity) then raise exception 'Inventory transfer issue would create negative physical balance' using errcode='23514'; end if;
  select iu.id into base_unit_id from public.inventory_item_units iu where iu.inventory_item_profile_id=allocation_row.inventory_item_profile_id and iu.active and iu.is_base_unit;
  entries:=entries||jsonb_build_array(jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',allocation_row.source_location_id,'disposition','available','quantity_base',-quantity),jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',transfer_row.transit_location_id,'disposition','transit','quantity_base',quantity));
 end loop;
 insert into public.inventory_transactions(tenant_id,organization_id,facility_id,command_id,transaction_type,posted_by,reason) values(transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,command_id,'transfer_issue',auth.uid(),trim(p_reason)) returning id into transaction_id; perform public.inventory_post_entries(transaction_id,entries,'inventory.transfer_issued',jsonb_build_object('transfer_id',p_transfer));
 for item in select value from jsonb_array_elements(p_issues) loop select ia.*,il.inventory_item_profile_id into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where ia.id=(item->>'transfer_allocation_id')::uuid; quantity:=(item->>'quantity_base')::numeric; insert into public.inventory_transfer_operations(transfer_id,transfer_allocation_id,command_id,transaction_id,operation_type,inventory_item_profile_id,batch_id,recording_channel,source_location_id,destination_location_id,source_disposition,destination_disposition,quantity_base,reason,created_by) values(p_transfer,allocation_row.id,command_id,transaction_id,'issue',allocation_row.inventory_item_profile_id,allocation_row.batch_id,allocation_row.recording_channel,allocation_row.source_location_id,transfer_row.transit_location_id,'available','transit',quantity,trim(p_reason),auth.uid()) returning id into operation_id; perform public.inventory_transfer_write_event(p_transfer,command_id,operation_id,'inventory.transfer_issued',jsonb_build_object('quantity_base',quantity)); end loop;
 update public.inventory_commands set status='posted',posted_at=now(),result_transaction_id=transaction_id,payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id; perform public.inventory_transfer_refresh_status(p_transfer); return p_transfer;
end $$;

create or replace function public.post_inventory_transfer_resolution(p_transfer uuid,p_type public.inventory_transfer_operation_type,p_moves jsonb,p_key text,p_hash text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; transaction_id uuid; item jsonb; allocation_row record; quantity numeric; issued numeric; received numeric; rejected_qty numeric; returned_qty numeric; disposed_qty numeric; destination uuid; from_disposition public.inventory_stock_disposition; to_disposition public.inventory_stock_disposition; entries jsonb:='[]'::jsonb; base_unit_id uuid; operation_id uuid; permission_key text; transaction_type public.inventory_transaction_type; begin
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 permission_key:=case p_type when 'receive' then 'inventory.transfer.receive' when 'reject' then 'inventory.transfer.reject' when 'return' then 'inventory.transfer.return' else 'inventory.transfer.dispose' end;
 transaction_type:=case p_type when 'receive' then 'transfer_receive' when 'reject' then 'transfer_reject' when 'return' then 'transfer_return' else 'transfer_dispose_rejected' end;
 if not found or jsonb_typeof(p_moves)<>'array' or jsonb_array_length(p_moves)=0 or coalesce(trim(p_reason),'')='' or not public.can_manage_inventory_transfer(p_transfer,permission_key) then raise exception 'Inventory transfer resolution denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,transaction_type,p_key,p_hash,jsonb_build_object('moves',p_moves),p_reason); if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for item in select value from jsonb_array_elements(p_moves) loop
  select ia.*,il.inventory_item_profile_id into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where ia.id=(item->>'transfer_allocation_id')::uuid and il.transfer_id=p_transfer for update; quantity:=(item->>'quantity_base')::numeric;
  if not found or quantity<=0 then raise exception 'Inventory transfer resolution denied'; end if;
  destination:=case when p_type='receive' then (item->>'destination_location_id')::uuid when p_type='return' then allocation_row.source_location_id else transfer_row.transit_location_id end;
  if p_type='receive' and (not public.inventory_transfer_location_allowed(transfer_row.destination_root_location_id,destination) or not public.can_manage_inventory_location(transfer_row.destination_root_location_id) or not public.can_manage_inventory_location(destination)) then raise exception 'Inventory transfer receipt destination denied'; end if;
  if p_type='receive' and exists(select 1 from public.inventory_batches b where b.id=allocation_row.batch_id and b.expiry_status<>'known_valid') and coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available')='available' then raise exception 'Expired or incomplete batch cannot be received as available' using errcode='23514'; end if;
  select coalesce(sum(quantity_base) filter(where operation_type='issue'),0),coalesce(sum(quantity_base) filter(where operation_type='receive'),0),coalesce(sum(quantity_base) filter(where operation_type='reject'),0),coalesce(sum(quantity_base) filter(where operation_type='return'),0),coalesce(sum(quantity_base) filter(where operation_type='dispose_rejected'),0) into issued,received,rejected_qty,returned_qty,disposed_qty from public.inventory_transfer_operations where transfer_allocation_id=allocation_row.id;
  if (p_type in ('receive','reject') and quantity>issued-received-rejected_qty) or (p_type in ('return','dispose_rejected') and quantity>rejected_qty-returned_qty-disposed_qty) then raise exception 'Inventory transfer resolution exceeds outstanding quantity' using errcode='23514'; end if;
  from_disposition:=case when p_type in ('receive','reject') then 'transit' else 'returns_hold' end;
  to_disposition:=case when p_type='receive' then coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available') when p_type='reject' then 'returns_hold' when p_type='return' then 'available' else coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'quarantine') end;
  if p_type='dispose_rejected' and to_disposition not in ('quarantine','damaged','expired','wastage_hold') then raise exception 'Inventory transfer disposition denied'; end if;
  select iu.id into base_unit_id from public.inventory_item_units iu where iu.inventory_item_profile_id=allocation_row.inventory_item_profile_id and iu.active and iu.is_base_unit;
  entries:=entries||jsonb_build_array(jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',transfer_row.transit_location_id,'disposition',from_disposition,'quantity_base',-quantity),jsonb_build_object('profile_id',allocation_row.inventory_item_profile_id,'batch_id',allocation_row.batch_id,'unit_id',base_unit_id,'channel',allocation_row.recording_channel,'account_type','physical','location_id',destination,'disposition',to_disposition,'quantity_base',quantity));
 end loop;
 insert into public.inventory_transactions(tenant_id,organization_id,facility_id,command_id,transaction_type,posted_by,reason) values(transfer_row.tenant_id,transfer_row.organization_id,transfer_row.facility_id,command_id,transaction_type,auth.uid(),trim(p_reason)) returning id into transaction_id; perform public.inventory_post_entries(transaction_id,entries,'inventory.transfer_'||p_type::text,jsonb_build_object('transfer_id',p_transfer));
 for item in select value from jsonb_array_elements(p_moves) loop
  select ia.*,il.inventory_item_profile_id into allocation_row from public.inventory_transfer_allocations ia join public.inventory_transfer_lines il on il.id=ia.transfer_line_id where ia.id=(item->>'transfer_allocation_id')::uuid; quantity:=(item->>'quantity_base')::numeric; destination:=case when p_type='receive' then (item->>'destination_location_id')::uuid when p_type='return' then allocation_row.source_location_id else transfer_row.transit_location_id end; from_disposition:=case when p_type in ('receive','reject') then 'transit' else 'returns_hold' end; to_disposition:=case when p_type='receive' then coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'available') when p_type='reject' then 'returns_hold' when p_type='return' then 'available' else coalesce((item->>'destination_disposition')::public.inventory_stock_disposition,'quarantine') end;
  insert into public.inventory_transfer_operations(transfer_id,transfer_allocation_id,command_id,transaction_id,operation_type,inventory_item_profile_id,batch_id,recording_channel,source_location_id,destination_location_id,source_disposition,destination_disposition,quantity_base,reason,created_by) values(p_transfer,allocation_row.id,command_id,transaction_id,p_type,allocation_row.inventory_item_profile_id,allocation_row.batch_id,allocation_row.recording_channel,transfer_row.transit_location_id,destination,from_disposition,to_disposition,quantity,trim(p_reason),auth.uid()) returning id into operation_id;
  if p_type='receive' then insert into public.inventory_transfer_receipt_destinations(operation_id,destination_location_id,inventory_item_profile_id,batch_id,recording_channel,quantity_base) values(operation_id,destination,allocation_row.inventory_item_profile_id,allocation_row.batch_id,allocation_row.recording_channel,quantity); end if;
  perform public.inventory_transfer_write_event(p_transfer,command_id,operation_id,'inventory.transfer_'||p_type::text,jsonb_build_object('quantity_base',quantity));
 end loop;
 update public.inventory_commands set status='posted',posted_at=now(),result_transaction_id=transaction_id,payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id; perform public.inventory_transfer_refresh_status(p_transfer); return p_transfer;
end $$;

create or replace function public.receive_inventory_transfer(p_transfer uuid,p_receipts jsonb,p_key text,p_hash text,p_reason text) returns uuid language sql security definer set search_path=public as $$ select public.post_inventory_transfer_resolution(p_transfer,'receive',p_receipts,p_key,p_hash,p_reason); $$;
create or replace function public.reject_inventory_transfer(p_transfer uuid,p_rejections jsonb,p_key text,p_hash text,p_reason text) returns uuid language sql security definer set search_path=public as $$ select public.post_inventory_transfer_resolution(p_transfer,'reject',p_rejections,p_key,p_hash,p_reason); $$;
create or replace function public.return_rejected_inventory_transfer(p_transfer uuid,p_returns jsonb,p_key text,p_hash text,p_reason text) returns uuid language sql security definer set search_path=public as $$ select public.post_inventory_transfer_resolution(p_transfer,'return',p_returns,p_key,p_hash,p_reason); $$;
create or replace function public.dispose_rejected_inventory_transfer(p_transfer uuid,p_disposals jsonb,p_key text,p_hash text,p_reason text) returns uuid language sql security definer set search_path=public as $$ select public.post_inventory_transfer_resolution(p_transfer,'dispose_rejected',p_disposals,p_key,p_hash,p_reason); $$;



create or replace function public.cancel_inventory_transfer(p_transfer uuid,p_key text,p_hash text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$ declare t public.inventory_transfers%rowtype; cmd uuid; r record; begin select * into t from public.inventory_transfers where id=p_transfer for update; if not found or t.status not in ('draft','reserved') or exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') or coalesce(trim(p_reason),'')='' or not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.cancel') then raise exception 'Inventory transfer cancellation denied'; end if; cmd:=public.claim_inventory_transfer_command(p_transfer,'transfer_cancel',p_key,p_hash,jsonb_build_object('transfer_id',p_transfer),p_reason); if (select payload ? 'result_transfer_id' from public.inventory_commands where id=cmd) then return p_transfer; end if; for r in select rr.id,public.inventory_transfer_reservation_remaining(rr.id) q from public.inventory_reservations rr join public.inventory_transfer_allocations a on a.id=rr.transfer_allocation_id join public.inventory_transfer_lines l on l.id=a.transfer_line_id where l.transfer_id=p_transfer loop if r.q>0 then insert into public.inventory_reservation_events(reservation_id,operation_type,quantity_base,reason,created_by) values(r.id,'reservation_released',r.q,trim(p_reason),auth.uid()); end if; end loop; insert into public.inventory_transfer_operations(transfer_id,command_id,operation_type,reason,created_by) values(p_transfer,cmd,'cancel',trim(p_reason),auth.uid()); update public.inventory_commands set status='posted',posted_at=now(),payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=cmd; perform public.inventory_transfer_refresh_status(p_transfer); perform public.inventory_transfer_write_event(p_transfer,cmd,null,'inventory.transfer_cancelled',jsonb_build_object('reason',trim(p_reason))); return p_transfer; end $$;

create or replace function public.close_inventory_transfer_remainder(p_transfer uuid,p_closures jsonb,p_key text,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare transfer_row public.inventory_transfers%rowtype; command_id uuid; closure_item jsonb; canonical jsonb; request_hash text; line_row public.inventory_transfer_lines%rowtype; allocation_row public.inventory_transfer_allocations%rowtype; reservation_row public.inventory_reservations%rowtype; quantity numeric; issued_qty numeric; closed_qty numeric; planned_qty numeric; line_new_qty numeric; line_new_unallocated_qty numeric; allocation_new_qty numeric; operation_id uuid; begin
 if jsonb_typeof(p_closures)<>'array' or jsonb_array_length(p_closures)=0 or coalesce(trim(p_reason),'')='' then raise exception 'Inventory transfer remainder closure denied'; end if;
 select jsonb_agg(value order by coalesce(value->>'transfer_allocation_id',''),value->>'transfer_line_id',value->>'quantity_base') into canonical from jsonb_array_elements(p_closures); request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('version',1,'action','transfer_close_remainder','transfer_id',p_transfer,'closures',canonical,'reason',trim(p_reason))::text,'utf8'),'sha256'),'hex');
 select * into transfer_row from public.inventory_transfers where id=p_transfer for update;
 if not found then raise exception 'Inventory transfer remainder closure denied'; end if;
 if transfer_row.status in ('draft','reserved','cancelled','completed') or not exists(select 1 from public.inventory_transfer_operations o where o.transfer_id=p_transfer and o.operation_type='issue') then raise exception 'Inventory transfer remainder closure lifecycle denied'; end if;
 if not public.can_manage_inventory_transfer(p_transfer,'inventory.transfer.close_remainder') then raise exception 'Inventory transfer remainder closure authorization denied'; end if;
 command_id:=public.claim_inventory_transfer_command(p_transfer,'transfer_close_remainder',p_key,request_hash,jsonb_build_object('version',1,'closures',canonical),trim(p_reason));
 if (select payload ? 'result_transfer_id' from public.inventory_commands where id=command_id) then return p_transfer; end if;
 for closure_item in select value from jsonb_array_elements(canonical) loop
  select * into line_row from public.inventory_transfer_lines l where l.id=(closure_item->>'transfer_line_id')::uuid and l.transfer_id=p_transfer for update; quantity:=(closure_item->>'quantity_base')::numeric; if not found or quantity<=0 or (closure_item->>'inventory_item_profile_id')::uuid is distinct from line_row.inventory_item_profile_id then raise exception 'Inventory transfer remainder closure denied'; end if;
  select coalesce(sum(o.quantity_base),0) into issued_qty from public.inventory_transfer_operations o join public.inventory_transfer_allocations a on a.id=o.transfer_allocation_id where a.transfer_line_id=line_row.id and o.operation_type='issue';
  select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_line_id=line_row.id;
  select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_new_qty from jsonb_array_elements(canonical) request_item where (request_item.value->>'transfer_line_id')::uuid=line_row.id;
  if issued_qty+closed_qty+line_new_qty>line_row.requested_quantity_base then raise exception 'Inventory transfer remainder closure exceeds line requested quantity' using errcode='23514'; end if;
  if closure_item ? 'transfer_allocation_id' and nullif(closure_item->>'transfer_allocation_id','') is not null then
   select * into allocation_row from public.inventory_transfer_allocations a where a.id=(closure_item->>'transfer_allocation_id')::uuid and a.transfer_line_id=line_row.id for update; if not found then raise exception 'Inventory transfer remainder closure allocation denied'; end if;
   select coalesce(sum(o.quantity_base),0) into issued_qty from public.inventory_transfer_operations o where o.transfer_allocation_id=allocation_row.id and o.operation_type='issue';
   select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_allocation_id=allocation_row.id;
   select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into allocation_new_qty from jsonb_array_elements(canonical) request_item where nullif(request_item.value->>'transfer_allocation_id','')::uuid=allocation_row.id;
   if issued_qty+closed_qty+allocation_new_qty>allocation_row.planned_quantity_base then raise exception 'Inventory transfer remainder closure exceeds allocation remaining' using errcode='23514'; end if;
   select * into reservation_row from public.inventory_reservations r where r.transfer_allocation_id=allocation_row.id for update;
   insert into public.inventory_transfer_remainder_closures(transfer_id,transfer_line_id,transfer_allocation_id,inventory_item_profile_id,reservation_id,quantity_base,command_id,reason,created_by) values(p_transfer,line_row.id,allocation_row.id,line_row.inventory_item_profile_id,reservation_row.id,quantity,command_id,trim(p_reason),auth.uid()) returning id into operation_id;
   if reservation_row.id is not null and quantity>public.inventory_transfer_reservation_remaining(reservation_row.id) then raise exception 'Inventory transfer remainder closure exceeds reservation remaining' using errcode='23514'; end if;
   if reservation_row.id is not null then insert into public.inventory_reservation_events(reservation_id,operation_type,quantity_base,reason,created_by) values(reservation_row.id,'reservation_released',quantity,trim(p_reason),auth.uid()); end if;
  else
   select coalesce(sum(a.planned_quantity_base),0) into planned_qty from public.inventory_transfer_allocations a where a.transfer_line_id=line_row.id;
   select coalesce(sum(c.quantity_base),0) into closed_qty from public.inventory_transfer_remainder_closures c where c.transfer_line_id=line_row.id and c.transfer_allocation_id is null;
   select coalesce(sum((request_item.value->>'quantity_base')::numeric),0) into line_new_unallocated_qty from jsonb_array_elements(canonical) request_item where (request_item.value->>'transfer_line_id')::uuid=line_row.id and nullif(request_item.value->>'transfer_allocation_id','') is null;
   if line_new_unallocated_qty+closed_qty>line_row.requested_quantity_base-coalesce(planned_qty,0) then raise exception 'Inventory transfer remainder closure exceeds line remaining' using errcode='23514'; end if;
   insert into public.inventory_transfer_remainder_closures(transfer_id,transfer_line_id,inventory_item_profile_id,quantity_base,command_id,reason,created_by) values(p_transfer,line_row.id,line_row.inventory_item_profile_id,quantity,command_id,trim(p_reason),auth.uid()) returning id into operation_id;
  end if;
  perform public.inventory_transfer_write_event(p_transfer,command_id,null,'inventory.transfer_remainder_closed',jsonb_build_object('closure_id',operation_id,'quantity_base',quantity));
 end loop;
 update public.inventory_commands set status='posted',posted_at=now(),payload=payload||jsonb_build_object('result_transfer_id',p_transfer) where id=command_id; perform public.inventory_transfer_refresh_status(p_transfer); return p_transfer;
end $$;
create or replace function public.expire_inventory_transfer_reservations() returns integer language plpgsql security definer set search_path=public as $$ declare r record; n integer:=0; begin if auth.role() not in ('service_role','postgres') then raise exception 'Inventory reservation expiry requires trusted execution'; end if; for r in select rr.id,public.inventory_transfer_reservation_remaining(rr.id) q from public.inventory_reservations rr where rr.expires_at<=now() loop if r.q>0 then insert into public.inventory_reservation_events(reservation_id,operation_type,quantity_base,reason,created_by) values(r.id,'reservation_expired',r.q,'reservation expiry',auth.uid()); n:=n+1; end if; end loop; return n; end $$;

alter table public.inventory_transfers enable row level security; alter table public.inventory_transfer_lines enable row level security; alter table public.inventory_transfer_allocations enable row level security; alter table public.inventory_reservations enable row level security; alter table public.inventory_reservation_events enable row level security; alter table public.inventory_transfer_operations enable row level security; alter table public.inventory_transfer_receipt_destinations enable row level security; alter table public.inventory_transfer_events enable row level security; alter table public.inventory_transfer_remainder_closures enable row level security;
create policy inventory_transfers_read on public.inventory_transfers for select using(public.can_view_inventory_transfer(id));
create policy inventory_transfer_lines_read on public.inventory_transfer_lines for select using(public.can_view_inventory_transfer(transfer_id));
create policy inventory_transfer_allocations_read on public.inventory_transfer_allocations for select using(exists(select 1 from public.inventory_transfer_lines l where l.id=transfer_line_id and public.can_view_inventory_transfer(l.transfer_id)));
create policy inventory_reservations_read on public.inventory_reservations for select using(exists(select 1 from public.inventory_transfer_allocations a join public.inventory_transfer_lines l on l.id=a.transfer_line_id where a.id=transfer_allocation_id and public.can_view_inventory_transfer(l.transfer_id)));
create policy inventory_reservation_events_read on public.inventory_reservation_events for select using(exists(select 1 from public.inventory_reservations r join public.inventory_transfer_allocations a on a.id=r.transfer_allocation_id join public.inventory_transfer_lines l on l.id=a.transfer_line_id where r.id=reservation_id and public.can_view_inventory_transfer(l.transfer_id)));
create policy inventory_transfer_operations_read on public.inventory_transfer_operations for select using(public.can_view_inventory_transfer(transfer_id));
create policy inventory_receipt_destinations_read on public.inventory_transfer_receipt_destinations for select using(exists(select 1 from public.inventory_transfer_operations o where o.id=operation_id and public.can_view_inventory_transfer(o.transfer_id)));
create policy inventory_transfer_events_read on public.inventory_transfer_events for select using(public.can_view_inventory_transfer(transfer_id));
create policy inventory_transfer_remainder_closures_read on public.inventory_transfer_remainder_closures for select using(public.can_view_inventory_transfer(transfer_id));
revoke all on public.inventory_transfers,public.inventory_transfer_lines,public.inventory_transfer_allocations,public.inventory_reservations,public.inventory_reservation_events,public.inventory_transfer_operations,public.inventory_transfer_receipt_destinations,public.inventory_transfer_events,public.inventory_transfer_remainder_closures from anon,authenticated;
grant select on public.inventory_transfers,public.inventory_transfer_lines,public.inventory_transfer_allocations,public.inventory_reservations,public.inventory_reservation_events,public.inventory_transfer_operations,public.inventory_transfer_receipt_destinations,public.inventory_transfer_events,public.inventory_transfer_remainder_closures,public.inventory_transfer_summary_projection,public.inventory_transfer_closure_summary to authenticated;
revoke all on function public.can_view_inventory_transfer(uuid),public.can_manage_inventory_transfer(uuid,text),public.inventory_transfer_location_allowed(uuid,uuid),public.inventory_transfer_write_event(uuid,uuid,uuid,text,jsonb),public.claim_inventory_transfer_command(uuid,public.inventory_transaction_type,text,text,jsonb,text),public.inventory_transfer_transit(uuid,uuid,uuid),public.enforce_inventory_transfer_integrity(),public.prevent_inventory_transfer_immutable_mutation(),public.enforce_transfer_receipt_destination(),public.inventory_transfer_reservation_remaining(uuid),public.inventory_transfer_refresh_status(uuid),public.post_inventory_transfer_resolution(uuid,public.inventory_transfer_operation_type,jsonb,text,text,text),public.expire_inventory_transfer_reservations() from public,anon,authenticated;
revoke all on function public.create_inventory_transfer(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,text),public.reserve_inventory_transfer(uuid,timestamptz,text,text),public.issue_inventory_transfer(uuid,jsonb,text,text,text),public.receive_inventory_transfer(uuid,jsonb,text,text,text),public.reject_inventory_transfer(uuid,jsonb,text,text,text),public.return_rejected_inventory_transfer(uuid,jsonb,text,text,text),public.dispose_rejected_inventory_transfer(uuid,jsonb,text,text,text),public.cancel_inventory_transfer(uuid,text,text,text),public.close_inventory_transfer_remainder(uuid,jsonb,text,text) from public,anon;
grant execute on function public.can_view_inventory_transfer(uuid),public.create_inventory_transfer(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,text),public.reserve_inventory_transfer(uuid,timestamptz,text,text),public.issue_inventory_transfer(uuid,jsonb,text,text,text),public.receive_inventory_transfer(uuid,jsonb,text,text,text),public.reject_inventory_transfer(uuid,jsonb,text,text,text),public.return_rejected_inventory_transfer(uuid,jsonb,text,text,text),public.dispose_rejected_inventory_transfer(uuid,jsonb,text,text,text),public.cancel_inventory_transfer(uuid,text,text,text),public.close_inventory_transfer_remainder(uuid,jsonb,text,text) to authenticated;
