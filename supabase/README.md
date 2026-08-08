# Nina Supabase Setup

This folder contains the first Supabase/Postgres backend for Nina.

## Apply the schema

Create a Supabase project, then apply every SQL file in `migrations/` in
filename order:

1. Supabase Dashboard > SQL Editor > paste and run the migration.
2. Supabase CLI after linking the project:

```sh
supabase link --project-ref <project-ref>
supabase db push
```

## Run automated tests

Run the iOS unit tests against an installed simulator:

```sh
xcodebuild \
  -project Nina.xcodeproj \
  -scheme Nina \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

Run the pgTAP database tests against the local Supabase stack:

```sh
npx supabase start
npx supabase db lint --local --fail-on error
npx supabase test db
```

The database tests run inside transactions and roll back their fixtures. The
checked-in GitHub Actions workflow repeats the iOS, web, Edge Function,
migration, and pgTAP checks on every pull request and push to `main`.

Before any production promotion, also run the repository and deployment gates
documented in `docs/production-launch-runbook.md`. The production preflight
cross-checks the Supabase/App Store values against the iOS source and verifies
the deployed health contract without printing secret values.

## Configure the iOS app

In the Supabase Dashboard, copy:

- Project URL
- Publishable key

Then set these generated Info.plist values on the Nina app target:

- `NINASupabaseURL`
- `NINASupabasePublishableKey`

The URL must be the root HTTPS project URL, without credentials, a path, query,
or fragment. Debug builds also allow `http://localhost`, `127.0.0.1`, or `::1`
for the local Supabase stack. The key must be a modern `sb_publishable_...` key
or a legacy JWT whose decoded role is exactly `anon`; the app rejects
`sb_secret_...`, service-role JWTs, and unresolved build placeholders before it
constructs a client.

For local development, copy `Nina/Config/SupabaseSecrets.xcconfig.example` to
`Nina/Config/SupabaseSecrets.xcconfig` and fill in the two values. The local
secrets file is ignored by Git.

In Debug builds, empty values use the local mock backend for previews and
development. Release builds show a configuration error and never grant local
family access.

Never put a Supabase secret key or service role key in the iOS app. The
migration enables Row Level Security so the publishable key can be used safely
from the client.

## Current app integration

When Supabase is configured, Nina now uses:

- Native Sign in with Apple as the only account-creation path.
- Six-digit email OTP as a secondary login after the address is linked from
  Settings.
- `profiles` for profile metadata.
- `families`, `family_members`, and server-managed `invites` for home creation,
  expiring/revocable invite links, joining, and membership access.
- Normalized tables as the source of truth for tasks, task sections, custom
  categories, shopping items, chat messages, and household insights. Scheduled
  and recurring reminders are task fields rather than a second entity.
- Supabase Realtime subscriptions for tasks, shopping items, and chat messages,
  scoped to the active family.
- Optimistic task locking with a server-managed version. Concurrent edits prompt
  the user to keep their edit or accept the latest remote version.
- Row-level inserts and updates from the iOS app. `family_snapshots` remains
  read-only only for legacy compatibility.
- Private Supabase Storage for profile photos. Each user can access only the
  folder matching their Auth user ID.
- An authenticated `nina-chat` Edge Function that reads RLS-scoped household
  context and calls the OpenAI Responses API.

The app keeps a local photo cache and a local Nina fallback so the UI remains
usable during temporary network or function failures.

Family access is never granted from the local cache. If Supabase cannot verify
the current `family_members` row, the app shows a retry/sign-out screen.

Family invite URLs use iOS Universal Links in the form
`https://ninai.app/invite/<token>`. The backend issues 128-bit tokens, expires
them after seven days, limits each link to seven distinct acceptances, records
accepted Auth user IDs, and revokes the previous link when it is rotated.

## Website waitlist

Migration `202607290001_web_waitlist.sql` creates a constrained server-only RPC
for launch signups. The RPC is executable only by the service role, and the
Cloudflare Worker calls it with a dedicated server-side `sb_secret_...` key so
public clients cannot choose arbitrary rate-limit fingerprints. It normalizes
and deduplicates email addresses, requires a versioned consent value, limits
requests using a salted short-lived fingerprint, and never stores a raw IP
address. The public website receives only a generic accepted response, so it
cannot reveal whether an email already exists.

Migration `202607290003_waitlist_unsubscribe.sql` adds a random cancellation
capability and a service-only `unsubscribe_waitlist_signup` RPC. A fresh consent
submission rotates the capability, so an older email cannot cancel newer
consent. The RPC gives the same response for active, unknown, stale, and
already-used capabilities.

Campaign jobs must read only rows where `status = 'subscribed'` and place the
capability in `https://ninai.app/unsubscribe/#<unsubscribe_token>`. The fragment
must not be changed to a path or query parameter because those forms can enter
HTTP access logs. Do not copy a long-lived waitlist export into an email
provider; filter at send time and synchronize withdrawals with any provider-side
schedule.

`run_waitlist_retention` removes withdrawn signups, expired abuse fingerprints,
and signups that have not renewed consent for 24 months. The daily
`nina-maintenance` function runs this cleanup independently of weekly AI insight
availability.

Migration `202608020001_waitlist_healthcheck.sql` adds a stable, service-only
health RPC. It references the current waitlist cancellation columns without
reading signup rows. The Cloudflare health endpoint combines that probe with a
public nonexistent-invite lookup, so `200` proves database reachability and the
expected migration contract rather than merely the presence of environment
variables. The RPC is not executable by `anon` or `authenticated`.

## Configure Auth

In the Supabase Dashboard:

1. Enable Apple and register the native client ID `com.heitor.nina`.
2. Keep email enabled, but disable email account creation.
3. Set the Magic Link/OTP and email-change templates to use `{{ .Token }}`.
4. Use a 6-digit OTP, 1-hour expiry, and 60-second request cooldown.
5. Disable double-confirm email changes so the new address confirms the change;
   keep the old-address security notification enabled.
6. Configure custom SMTP before production. Supabase's default sender is only
   suitable for development.

The checked-in `config.toml` contains the provider-independent Auth settings.
After linking the intended project, review the diff and apply them with
`supabase config push`.

The ready-to-use HTML bodies live in `templates/`. Supabase free-tier projects
using the default email provider reject custom template updates, so configure
custom SMTP first, then install these bodies in the Dashboard's Email Templates
and Security Notifications pages.

## Deploy Premium verification

The iOS app sends StoreKit 2 transaction JWS values to
`premium-subscription-sync`. App Store Server Notifications V2 must target:

```text
https://<project-ref>.supabase.co/functions/v1/app-store-server-notifications
```

Copy `supabase/.env.example` to the ignored `supabase/.env.local` and configure:

- `NINA_APP_BUNDLE_ID=com.heitor.nina`
- `NINA_APP_APPLE_ID`: the positive numeric Apple ID from App Store Connect
- `NINA_PREMIUM_PRODUCT_IDS`: the exact monthly/yearly product identifiers
- `NINA_APP_STORE_ENVIRONMENT=production`
- `NINA_APP_STORE_ONLINE_CHECKS=true`

Then upload secrets and deploy both functions:

```sh
npx supabase secrets set --env-file supabase/.env.local --project-ref <project-ref>
npx supabase functions deploy premium-subscription-sync --project-ref <project-ref> --use-api
npx supabase functions deploy app-store-server-notifications --project-ref <project-ref> --use-api
```

Production must use the explicit `production` environment. Use a separate
Supabase test project configured as `sandbox`, `xcode`, or `local_testing`;
never enable those values in the public production project. If the environment
is omitted, the verifier accepts only Apple's public Production and Sandbox
chains, never Xcode or Local Testing. Invalid values fail closed.

Keep online certificate checks enabled. The functions accept only bounded JSON
bodies and valid compact-JWS shapes, limit verification time, and fetch Apple's
root certificates with bounded downloads and retryable timeouts. For a
production deployment that must not depend on certificate downloads at cold
start, provide the official Apple root certificates through
`APPLE_ROOT_CA_PEMS`.

In App Store Connect, configure the production notification URL, send Apple's
test notification, and confirm a `200` response plus a row in
`app_store_server_notifications` before enabling subscriptions for sale.

## Deploy Nina chat

The local OpenAI key belongs only in `supabase/.env.local`, which is ignored by
Git. Never add it to the iOS target or an xcconfig file.

After applying the latest migration, authenticate and deploy with the Supabase
CLI:

```sh
npx supabase login
npx supabase secrets set --env-file supabase/.env.local --project-ref apemftmlsjocvifbptum
npx supabase functions deploy nina-chat --project-ref apemftmlsjocvifbptum --use-api
```

Deploy the account deletion function with the same Supabase secret
configuration:

```sh
npx supabase functions deploy delete-account --project-ref apemftmlsjocvifbptum --use-api
```

`delete-account` must have access to `SUPABASE_SERVICE_ROLE_KEY` or
`SUPABASE_SECRET_KEYS` in Supabase function secrets. The iOS app calls it with
the user's JWT and the exact JSON body `{"confirmation":"delete"}`; the service
role key must never be shipped in the app. Apply
`202608020002_account_deletion_transaction.sql` before deploying the function.
The function deletes profile photos in bounded pages and batches, calls the
service-only transactional preparation RPC, then deletes the Auth user. A
database trigger repeats the idempotent preparation inside the Auth deletion
transaction to close late-reference races. Failure logs contain only a request
ID and stage.

Interactive Nina chat uses `gpt-5.4-mini`. Model selection is fixed in the
function so a deployment environment override cannot silently change the budget
model or response behavior.

Household context required for each reply is sent from the Edge Function to
OpenAI with API response storage disabled (`store: false`).

The OpenAI project must have API billing or credits enabled. A valid key without
available quota will return `429 insufficient_quota`.

## Nina AI V2

Nina AI V2 keeps OpenAI access in Edge Functions and adds:

- private adult-owned chat threads;
- read-only household tools and confirmation-only proposals;
- confirmed private/shared memories;
- 30-day chat and resolved-proposal retention;
- 90-day operational-log and insight retention;
- 30 requests per user/hour and 100 requests per family/day;
- a hard monthly application budget of US$20 for chat and US$5 for insights;
- daily maintenance and weekly family insights;
- content-free run logs with token, latency, status, and cost metadata.

Run the Edge contract tests:

```sh
npx deno check supabase/functions/nina-chat/index.ts
npx deno test --allow-read supabase/functions/_shared/nina-ai.test.ts
```

Run the live Portuguese evaluation against the linked test project:

```sh
node Tools/run_nina_ai_eval.mjs apemftmlsjocvifbptum
```

The evaluator creates disposable adults and a family, temporarily enables
password auth only for those fixtures, runs every case in
`functions/nina-chat/evals/pt-BR.json`, writes aggregate and per-case metadata
to `functions/nina-chat/evals/latest-report.json`, and restores Auth settings
and deletes all fixtures. It never stores assistant replies or household content
in the report.

Keep `NINA_AI_V2_ENABLED = NO` for general builds until the test-account rollout
is approved. Enable it in the ignored local secrets xcconfig or the release
configuration used for the selected test accounts.

The database enforces the hard US$25 cap. Also set the OpenAI project
**Monthly budget** to US$25 under Platform **Project > Limits** as a secondary
soft alert; OpenAI project budgets do not stop API requests.

## Privacy launch artifacts

- Public privacy policy: `web/src/pages/privacidade.astro`
- App Store privacy labels: `docs/privacy/app-store-privacy-labels.md`
- LGPD posture checklist: `docs/privacy/lgpd-launch-posture.md`

Before production App Store submission, deploy `https://ninai.app/privacidade`
and confirm it includes the final legal entity and privacy contact.
