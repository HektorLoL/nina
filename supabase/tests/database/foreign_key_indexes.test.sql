begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

select is(
  (
    select count(*)::integer
    from pg_constraint as constraints
    join pg_namespace as namespaces on namespaces.oid = constraints.connamespace
    where constraints.contype = 'f'
      and namespaces.nspname in ('public', 'private')
      and not exists (
        select 1
        from pg_index as indexes
        where indexes.indrelid = constraints.conrelid
          and (indexes.indkey::int2[])[0:array_length(constraints.conkey, 1) - 1] = constraints.conkey
      )
  ),
  0,
  'every foreign key in public and private has an index that leads with its columns'
);

select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.set_updated_at()'::regprocedure
      and proconfig::text like '%search_path=pg_catalog, public%'
  ),
  'set_updated_at runs with a fixed search_path'
);

select * from finish();
rollback;
