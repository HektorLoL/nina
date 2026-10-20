begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('c1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', null, '{}'::jsonb, now(), now()),
  ('c1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', null, '{}'::jsonb, now(), now());

-- Every fixture account is an Apple-confirmed adult unless a test says otherwise.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id in ('c1000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002')
on conflict (user_id) do nothing;

select ok(
  (select relrowsecurity from pg_class where oid = 'private.app_access_records'::regclass)
    and not has_table_privilege('anon', 'private.app_access_records', 'select')
    and not has_table_privilege('authenticated', 'private.app_access_records', 'select')
    and not has_table_privilege('service_role', 'private.app_access_records', 'select')
    and not has_table_privilege('service_role', 'private.app_access_records', 'insert'),
  'no API role reads or writes the access records, which keep row level security on'
);

select ok(
  not has_function_privilege('authenticated', 'private.record_app_access(uuid)', 'execute')
    and not has_function_privilege('service_role', 'private.record_app_access(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.request_client_address()', 'execute')
    and not has_function_privilege('anon', 'private.request_client_address()', 'execute'),
  'no API role writes an access record or reads the address directly'
);

select ok(
  not exists (
    select 1
    from pg_constraint
    where conrelid = 'private.app_access_records'::regclass
      and contype = 'f'
  ),
  'an access record carries no foreign key, so it outlives the account it names'
);

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000001';
select set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7","x-forwarded-for":"198.51.100.9, 10.0.0.1"}', true);

select lives_ok(
  $$select public.ensure_current_profile(null)$$,
  'loading the profile through the API succeeds while it records the access'
);

reset role;

select is(
  (
    select array_agg(host(ip_address) order by first_seen_at)
    from private.app_access_records
    where user_id = 'c1000000-0000-4000-8000-000000000001'
  ),
  array['203.0.113.7'],
  'the access is recorded from Cloudflare''s connecting address, never from the client''s own x-forwarded-for'
);

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.get_current_home_context()$$,
  'a home load from the same address within thirty minutes succeeds'
);

reset role;

select is(
  (select count(*)::integer from private.app_access_records where user_id = 'c1000000-0000-4000-8000-000000000001'),
  1,
  'a use from the same address within thirty minutes extends the record instead of adding one'
);

update private.app_access_records
set first_seen_at = now() - interval '2 hours', last_seen_at = now() - interval '1 hour'
where user_id = 'c1000000-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000001';
select public.ensure_current_profile(null);
select set_config('request.headers', '{"cf-connecting-ip":"2001:db8::5"}', true);
select public.ensure_current_profile(null);
reset role;

select is(
  (
    select array_agg(host(ip_address) order by first_seen_at, id)
    from private.app_access_records
    where user_id = 'c1000000-0000-4000-8000-000000000001'
  ),
  array['203.0.113.7', '203.0.113.7', '2001:db8::5'],
  'a use after thirty minutes away or from another address starts a new record, IPv6 included'
);

select ok(
  (select bool_and(source_port is null and last_seen_at >= first_seen_at) from private.app_access_records),
  'no header carries the source port, so it stays empty and every window runs forward'
);

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000002';
select set_config('request.headers', '{"x-forwarded-for":"198.51.100.9"}', true);

select lives_ok(
  $$select public.ensure_current_profile(null)$$,
  'a request without Cloudflare''s header still loads'
);

select set_config('request.headers', '{"cf-connecting-ip":"240.0.0.9","cf-connecting-ipv6":"2001:db8::77"}', true);
select public.ensure_current_profile(null);
select set_config('request.headers', '{"cf-connecting-ip":"198.51.100.20","cf-connecting-ipv6":"2001:db8::66"}', true);
select public.ensure_current_profile(null);

reset role;

select is(
  (
    select array_agg(host(ip_address) order by host(ip_address))
    from private.app_access_records
    where user_id = 'c1000000-0000-4000-8000-000000000002'
  ),
  array['198.51.100.20', '2001:db8::77'],
  'the IPv6 header is read only behind a Cloudflare pseudo address, never beside a real one'
);

delete from private.app_access_records where user_id = 'c1000000-0000-4000-8000-000000000002';

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000002';
select set_config('request.headers', '{"cf-connecting-ip":"not an address"}', true);

select lives_ok(
  $$select public.ensure_current_profile(null)$$,
  'a request with an unreadable address still loads'
);

select set_config('request.headers', '', true);

select lives_ok(
  $$select public.ensure_current_profile(null)$$,
  'a call with no request headers at all still loads'
);

reset role;

select is(
  (select count(*)::integer from private.app_access_records where user_id = 'c1000000-0000-4000-8000-000000000002'),
  0,
  'nothing is recorded without an address Cloudflare vouched for'
);

delete from auth.users where id = 'c1000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from private.app_access_records where user_id = 'c1000000-0000-4000-8000-000000000001'),
  3,
  'deleting the account leaves its access records for their six months'
);

insert into private.app_access_records (user_id, ip_address, first_seen_at, last_seen_at, kept_until)
values
  ('c1000000-0000-4000-8000-000000000003', '192.0.2.1', now() - interval '7 months', now() - interval '7 months', null),
  ('c1000000-0000-4000-8000-000000000003', '192.0.2.2', now() - interval '5 months', now() - interval '5 months', null),
  ('c1000000-0000-4000-8000-000000000003', '192.0.2.3', now() - interval '7 months', now() - interval '7 months', now() + interval '30 days'),
  ('c1000000-0000-4000-8000-000000000004', '192.0.2.4', now() - interval '7 months', now() - interval '7 months', null),
  ('c1000000-0000-4000-8000-000000000005', '192.0.2.5', now() - interval '7 months', now() - interval '7 months', null);

insert into private.child_safety_holds (user_id, content)
values ('c1000000-0000-4000-8000-000000000004', 'conteúdo retido');

insert into private.child_safety_holds (user_id, content, deleted_at)
values ('c1000000-0000-4000-8000-000000000005', '', now());

set local role service_role;

select is(
  public.run_nina_retention() ->> 'access_records',
  '2',
  'retention reports how many access records it deleted'
);

reset role;

select is(
  (
    select array_agg(host(ip_address) order by host(ip_address))
    from private.app_access_records
    where user_id in (
      'c1000000-0000-4000-8000-000000000003',
      'c1000000-0000-4000-8000-000000000004',
      'c1000000-0000-4000-8000-000000000005'
    )
  ),
  array['192.0.2.2', '192.0.2.3', '192.0.2.4'],
  'retention drops a record six months after its last use, unless an authority asked for longer or a hold on its account is preserved'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'private.app_access_record_reads'::regclass)
    and not has_table_privilege('service_role', 'private.app_access_record_reads', 'select')
    and not has_function_privilege('service_role', 'private.operator_read_access_records(text,text,uuid,inet,timestamptz,timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'private.operator_read_access_records(text,text,uuid,inet,timestamptz,timestamptz)', 'execute'),
  'only the operator reads the access records, and no API role sees who read them'
);

select throws_ok(
  $$select * from private.operator_read_access_records('Heitor', '  ', 'c1000000-0000-4000-8000-000000000003', null, now() - interval '1 year', now())$$,
  '22023',
  'case_reference_required',
  'a read without a case reference is refused'
);

select throws_ok(
  $$select * from private.operator_read_access_records('', 'Processo 1', 'c1000000-0000-4000-8000-000000000003', null, now() - interval '1 year', now())$$,
  '22023',
  'reader_name_required',
  'a read without the name of the person reading is refused'
);

select is(
  (
    select array_agg(host(ip_address) order by host(ip_address))
    from private.operator_read_access_records('Heitor', 'Processo 0000000-00.2026.8.19.0001', 'c1000000-0000-4000-8000-000000000003', null, now() - interval '1 year', now())
  ),
  array['192.0.2.2', '192.0.2.3'],
  'the operator reads the records of one account inside a period'
);

select is(
  (
    select array[read_by, case_reference, rows_returned::text, target_user_id::text]
    from private.app_access_record_reads
    order by id desc
    limit 1
  ),
  array['Heitor', 'Processo 0000000-00.2026.8.19.0001', '2', 'c1000000-0000-4000-8000-000000000003'],
  'every read through the operator function leaves a line with who read, the case, the target and the rows returned'
);

insert into private.app_access_records (user_id, ip_address, first_seen_at, last_seen_at)
select 'c1000000-0000-4000-8000-000000000006', ('10.9.' || (n / 256) || '.' || (n % 256))::inet, now() - interval '1 hour', now() - interval '1 hour'
from generate_series(1, 500) as n;

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values ('c1000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', null, '{}'::jsonb, now(), now());

set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-4000-8000-000000000006';
select set_config('request.headers', '{"cf-connecting-ip":"203.0.113.99"}', true);

select lives_ok(
  $$select public.ensure_current_profile(null)$$,
  'an account past 500 new addresses in a day still loads'
);

reset role;

select is(
  (select count(*)::integer from private.app_access_records where user_id = 'c1000000-0000-4000-8000-000000000006'),
  500,
  'one account adds at most 500 new address records a day, so rotating addresses cannot flood the table'
);

select * from finish();
rollback;
