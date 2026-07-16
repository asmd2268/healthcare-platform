-- Kept separate because PostgreSQL cannot use a newly added enum value in a
-- constraint until the transaction that added it has committed.
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_create'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_reserve'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_issue'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_receive'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_reject'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_return'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_dispose_rejected'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_cancel'; exception when duplicate_object then null; end $$;
do $$ begin alter type public.inventory_transaction_type add value if not exists 'transfer_close_remainder'; exception when duplicate_object then null; end $$;
