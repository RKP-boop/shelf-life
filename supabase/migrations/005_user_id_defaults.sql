-- ShelfLife MVP — default user_id to the caller
--
-- Found by verification: an insert that omitted user_id was rejected with
-- "new row violates row-level security policy". The RLS check is
-- `user_id = auth.uid()`, and a null user_id can never satisfy it.
--
-- Requiring every client insert to carry user_id explicitly works, but makes a
-- whole class of silent client bugs possible: forget the field anywhere and the
-- write fails at runtime with an error that reads like a permissions problem
-- rather than a missing column. Defaulting it removes the possibility.
--
-- This does NOT weaken security. The RLS `with check (user_id = auth.uid())`
-- policies still apply, so a client that explicitly sends someone else's
-- user_id is still refused; the default only fills in the correct value when
-- the field is absent.

alter table inventory_items     alter column user_id set default auth.uid();
alter table consumption_events  alter column user_id set default auth.uid();
alter table shopping_list_items alter column user_id set default auth.uid();
alter table notifications       alter column user_id set default auth.uid();

-- Same reasoning for products.contributed_by: the insert policy requires
-- `contributed_by = auth.uid()`, so a null would always be refused.
alter table products alter column contributed_by set default auth.uid();

comment on column inventory_items.user_id is
  'Defaults to auth.uid(). RLS still enforces user_id = auth.uid() on insert and update, so the default is a convenience, not a privilege.';
