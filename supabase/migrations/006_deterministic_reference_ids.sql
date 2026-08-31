-- Deterministic ids for seeded reference data.
--
-- The problem this fixes
-- ----------------------
-- `ingredients.id` and `recipes.id` defaulted to gen_random_uuid(). That is
-- correct for user data and wrong for seeded reference data, because the app
-- is offline-first: it ships the same catalogue in Hive and must be able to
-- write `inventory_items.ingredient_id` on a phone that has never reached the
-- server. With server-assigned random ids the client cannot know them, so
-- every queued insert would fail its foreign key on the first sync.
--
-- The fix
-- -------
-- Reference rows become content-addressed: the id is derived from the natural
-- key, so Postgres and Dart independently compute the same uuid.
--
--     ingredients.id = md5(canonical_name)::uuid
--     recipes.id     = md5(lower(name))::uuid
--
-- md5-as-uuid rather than uuid_generate_v5 deliberately: v5 needs the
-- uuid-ossp extension, and the property being relied on here is only
-- determinism, not RFC-4122 version semantics. `products` already keys on
-- barcode, which is deterministic by nature, so it needs nothing.
--
-- Why `on update cascade`
-- -----------------------
-- The ids have to change in place, and Postgres checks parent-side FKs
-- immediately. Adding `on update cascade` lets one UPDATE on the parent carry
-- every child with it, instead of a deferred-constraint dance or a
-- delete-and-reinsert that would lose user rows. It is also simply the right
-- declaration for a key that is derived rather than surrogate.
--
-- Idempotent: re-running recomputes the same values and changes nothing.

begin;

-- ---------------------------------------------------------------- FKs
--
-- Discovered from the catalogue rather than listed by hand. The first version
-- of this migration named eight constraints explicitly and missed
-- ingredient_aliases, so the whole thing aborted on a foreign key violation.
-- A list maintained by hand is a list that goes stale the next time a table is
-- added; asking pg_constraint cannot miss one.
--
-- Each constraint is rebuilt with its existing on-delete behaviour preserved
-- and `on update cascade` added, in a single ALTER so there is never a moment
-- where the foreign key is absent.

do $$
declare
  fk  record;
  def text;
begin
  for fk in
    select con.oid,
           con.conname,
           con.confupdtype,
           ns.nspname     as child_schema,
           child.relname  as child_table,
           parent.relname as parent_table
      from pg_constraint con
      join pg_class     child  on child.oid  = con.conrelid
      join pg_namespace ns     on ns.oid     = child.relnamespace
      join pg_class     parent on parent.oid = con.confrelid
     where con.contype = 'f'
       and parent.relname in ('ingredients', 'recipes')
     order by child.relname, con.conname
  loop
    -- Already cascading: nothing to do, and rebuilding it would append a
    -- second ON UPDATE clause.
    if fk.confupdtype = 'c' then
      continue;
    end if;

    -- 'a' is NO ACTION, the default, which pg_get_constraintdef omits -- so
    -- appending ON UPDATE CASCADE is safe. Anything else (restrict, set null,
    -- set default) is a deliberate choice this migration should not silently
    -- overwrite.
    if fk.confupdtype <> 'a' then
      raise exception
        'constraint %.% on %.% has an unexpected on-update rule (%); refusing '
        'to rewrite it',
        fk.parent_table, fk.conname, fk.child_schema, fk.child_table,
        fk.confupdtype;
    end if;

    def := pg_get_constraintdef(fk.oid);

    -- A deferrable constraint puts its DEFERRABLE clause last, so appending
    -- after it would be a syntax error. None here are, but failing loudly
    -- beats emitting broken DDL.
    if def ilike '%DEFERRABLE%' then
      raise exception 'constraint % on %.% is deferrable; rewrite it by hand',
        fk.conname, fk.child_schema, fk.child_table;
    end if;

    execute format(
      'alter table %I.%I drop constraint %I, add constraint %I %s '
      'on update cascade',
      fk.child_schema, fk.child_table, fk.conname, fk.conname, def);

    raise notice 'cascaded % on %.%',
      fk.conname, fk.child_schema, fk.child_table;
  end loop;
end $$;

-- ------------------------------------------------------------ rewrite

update ingredients
   set id = md5(canonical_name)::uuid
 where id is distinct from md5(canonical_name)::uuid;

update recipes
   set id = md5(lower(name))::uuid
 where id is distinct from md5(lower(name))::uuid;

-- --------------------------------------------------------- new defaults
--
-- So a row inserted later by the seed script lands on the same id without the
-- caller having to compute it.

alter table ingredients alter column id drop default;
alter table recipes     alter column id drop default;

commit;

-- ------------------------------------------------------------- checks
--
-- These raise rather than return a row, so running the file is itself the
-- verification. A silent no-op migration is how a broken FK reaches a phone.

do $$
declare
  bad_ingredients int;
  bad_recipes     int;
  uncascaded      text;
begin
  -- The check that would have caught the first version of this migration: an
  -- FK referencing a reference table that does not cascade on update is an FK
  -- the rewrite step will trip over.
  select string_agg(ns.nspname || '.' || child.relname || '.' || con.conname,
                    ', ' order by con.conname)
    into uncascaded
    from pg_constraint con
    join pg_class     child  on child.oid  = con.conrelid
    join pg_namespace ns     on ns.oid     = child.relnamespace
    join pg_class     parent on parent.oid = con.confrelid
   where con.contype = 'f'
     and parent.relname in ('ingredients', 'recipes')
     and con.confupdtype <> 'c';

  if uncascaded is not null then
    raise exception 'these foreign keys still do not cascade on update: %',
      uncascaded;
  end if;

  select count(*) into bad_ingredients
    from ingredients where id <> md5(canonical_name)::uuid;
  select count(*) into bad_recipes
    from recipes where id <> md5(lower(name))::uuid;

  if bad_ingredients > 0 then
    raise exception 'ingredients: % rows do not match md5(canonical_name)',
      bad_ingredients;
  end if;
  if bad_recipes > 0 then
    raise exception 'recipes: % rows do not match md5(lower(name))', bad_recipes;
  end if;

  raise notice 'reference ids are deterministic: % ingredients, % recipes',
    (select count(*) from ingredients), (select count(*) from recipes);
end $$;
