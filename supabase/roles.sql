-- The production project was created with these default privileges, so every
-- migration replayed here must grant what it granted there. Only a database
-- with no migration history takes them, so a push that includes roles never
-- widens production again.
do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    if exists (select 1 from supabase_migrations.schema_migrations) then
      return;
    end if;
  end if;

  alter default privileges for role postgres in schema public
    grant all on tables to anon, authenticated, service_role;
  alter default privileges for role postgres in schema public
    grant all on functions to anon, authenticated, service_role;
  alter default privileges for role postgres in schema public
    grant all on sequences to anon, authenticated, service_role;
end;
$$;
