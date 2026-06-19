create table public.premium_subscriptions (
  original_transaction_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  app_account_token uuid,
  product_id text not null,
  environment text not null,
  status text not null default 'inactive'
    check (status in ('inactive', 'active', 'grace_period', 'billing_retry', 'expired', 'revoked')),
  is_active boolean not null default false,
  transaction_id text not null,
  web_order_line_item_id text,
  purchased_at timestamptz,
  original_purchase_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,
  grace_period_expires_at timestamptz,
  will_renew boolean,
  auto_renew_status text,
  auto_renew_product_id text,
  expiration_intent text,
  signed_transaction_info text not null,
  signed_renewal_info text,
  raw_transaction jsonb not null default '{}'::jsonb,
  raw_renewal_info jsonb not null default '{}'::jsonb,
  latest_notification_type text,
  latest_notification_subtype text,
  latest_notification_uuid text,
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index premium_subscriptions_user_active_idx
  on public.premium_subscriptions(user_id, is_active, expires_at desc);

create index premium_subscriptions_transaction_idx
  on public.premium_subscriptions(transaction_id);

create table public.premium_subscription_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_id text not null unique,
  original_transaction_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  app_account_token uuid,
  product_id text not null,
  environment text not null,
  product_type text,
  ownership_type text,
  source text not null,
  purchased_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  signed_transaction_info text not null,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index premium_subscription_transactions_user_idx
  on public.premium_subscription_transactions(user_id, purchased_at desc);

create index premium_subscription_transactions_original_idx
  on public.premium_subscription_transactions(original_transaction_id);

create table public.app_store_server_notifications (
  notification_uuid text primary key,
  notification_type text,
  notification_subtype text,
  environment text,
  app_apple_id bigint,
  bundle_id text,
  original_transaction_id text,
  transaction_id text,
  user_id uuid references auth.users(id) on delete set null,
  signed_payload text not null,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create index app_store_server_notifications_user_idx
  on public.app_store_server_notifications(user_id, received_at desc);

create index app_store_server_notifications_original_idx
  on public.app_store_server_notifications(original_transaction_id);

create trigger premium_subscriptions_set_updated_at
  before update on public.premium_subscriptions
  for each row execute function public.set_updated_at();

create trigger premium_subscription_transactions_set_updated_at
  before update on public.premium_subscription_transactions
  for each row execute function public.set_updated_at();

alter table public.premium_subscriptions enable row level security;
alter table public.premium_subscription_transactions enable row level security;
alter table public.app_store_server_notifications enable row level security;

revoke all on table public.premium_subscriptions from public, anon, authenticated;
revoke all on table public.premium_subscription_transactions from public, anon, authenticated;
revoke all on table public.app_store_server_notifications from public, anon, authenticated;

grant select on table public.premium_subscriptions to authenticated;
grant select on table public.premium_subscription_transactions to authenticated;

grant select, insert, update, delete on table public.premium_subscriptions to service_role;
grant select, insert, update, delete on table public.premium_subscription_transactions to service_role;
grant select, insert, update, delete on table public.app_store_server_notifications to service_role;

create policy "Users can read own premium subscriptions"
  on public.premium_subscriptions
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users can read own premium transactions"
  on public.premium_subscription_transactions
  for select
  to authenticated
  using (user_id = auth.uid());

create or replace function public.get_current_premium_status()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
  with latest_subscription as (
    select *
    from public.premium_subscriptions
    where user_id = auth.uid()
    order by
      is_active desc,
      expires_at desc nulls last,
      last_verified_at desc,
      updated_at desc
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'is_active', latest_subscription.is_active,
        'status', latest_subscription.status,
        'product_id', latest_subscription.product_id,
        'expires_at', latest_subscription.expires_at,
        'will_renew', latest_subscription.will_renew,
        'environment', latest_subscription.environment,
        'original_transaction_id', latest_subscription.original_transaction_id,
        'latest_transaction_id', latest_subscription.transaction_id,
        'last_verified_at', latest_subscription.last_verified_at
      )
      from latest_subscription
    ),
    jsonb_build_object(
      'is_active', false,
      'status', 'inactive',
      'product_id', null,
      'expires_at', null,
      'will_renew', null,
      'environment', null,
      'original_transaction_id', null,
      'latest_transaction_id', null,
      'last_verified_at', null
    )
  );
$$;

revoke all on function public.get_current_premium_status() from public, anon, authenticated, service_role;
grant execute on function public.get_current_premium_status() to authenticated;
