begin;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'inventory_locations','inventory_balance_projections','inventory_transfers',
    'inventory_transfer_lines','inventory_transfer_allocations','inventory_reservations',
    'inventory_reservation_adjustments','inventory_transfer_operations',
    'inventory_transfer_receipt_destinations','inventory_transfer_events',
    'inventory_transfer_remainder_closures'
  ] loop
    if not has_table_privilege('authenticated',format('public.%I',table_name),'select') then
      raise exception 'authenticated SELECT missing for %',table_name;
    end if;
    if has_table_privilege('anon',format('public.%I',table_name),'select') then
      raise exception 'anon unexpectedly has SELECT for %',table_name;
    end if;
    if not coalesce((select relrowsecurity from pg_class where oid=format('public.%I',table_name)::regclass),false) then
      raise exception 'RLS missing for %',table_name;
    end if;
  end loop;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','79000000-0000-0000-0000-000000000001',true);

do $$
begin
  if exists(select 1 from public.inventory_locations)
    or exists(select 1 from public.inventory_balance_projections)
    or exists(select 1 from public.inventory_transfers)
    or exists(select 1 from public.inventory_transfer_lines)
    or exists(select 1 from public.inventory_transfer_allocations)
    or exists(select 1 from public.inventory_reservations)
    or exists(select 1 from public.inventory_reservation_adjustments)
    or exists(select 1 from public.inventory_transfer_operations)
    or exists(select 1 from public.inventory_transfer_receipt_destinations)
    or exists(select 1 from public.inventory_transfer_events)
    or exists(select 1 from public.inventory_transfer_remainder_closures) then
    raise exception 'unscoped authenticated inventory reader unexpectedly observed protected rows';
  end if;
end $$;

rollback;
