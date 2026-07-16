-- Reservation expiry accounting types.
-- Kept separate because newly-added PostgreSQL enum values must be committed
-- before they are safely referenced by later migration statements.

do $$
begin
  alter type public.inventory_transaction_type
    add value if not exists 'transfer_reservation_expire';
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter type public.inventory_reservation_adjustment_type
    add value if not exists 'expiry_released';
exception
  when duplicate_object then null;
end
$$;
