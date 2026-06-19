# Nina Supabase Setup

This folder contains the first Supabase/Postgres backend for Nina.

## Apply the schema

Create a Supabase project, then apply every SQL file in `migrations/` in filename order:

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
npx supabase test db
```

The database tests run inside transactions and roll back their fixtures.

## Configure the iOS app

In the Supabase Dashboard, copy:

- Project URL
- Publishable key

Then set these generated Info.plist values on the Nina app target:

- `NINASupabaseURL`
- `NINASupabasePublishableKey`

For local development, copy `Nina/Config/SupabaseSecrets.xcconfig.example` to
`Nina/Config/SupabaseSecrets.xcconfig` and fill in the two values. The local
secrets file is ignored by Git.

In Debug builds, empty values use the local mock backend for previews and
development. Release builds show a configuration error and never grant local
family access.

Never put a Supabase secret key or service role key in the iOS app. The migration enables Row Level Security so the publishable key can be used safely from the client.

## Current app integration

When Supabase is configured, Nina now uses:

- Native Sign in with Apple as the only account-creation path.
- Six-digit email OTP as a secondary login after the address is linked from Settings.
- `profiles` for profile metadata.
- `families`, `family_members`, and server-managed `invites` for home creation,
  expiring/revocable invite links, joining, and membership access.
- Normalized tables as the source of truth for tasks, task sections, custom categories, shopping items, reminders, chat messages, and household insights.
- Supabase Realtime subscriptions for tasks, shopping items, reminders, and chat messages, scoped to the active family.
- Optimistic task locking with a server-managed version. Concurrent edits prompt the user to keep their edit or accept the latest remote version.
- Row-level inserts and updates from the iOS app. `family_snapshots` remains read-only only for legacy compatibility.
- Private Supabase Storage for profile photos. Each user can access only the folder matching their Auth user ID.
- An authenticated `nina-chat` Edge Function that reads RLS-scoped household context and calls the OpenAI Responses API.

The app keeps a local photo cache and a local Nina fallback so the UI remains usable during temporary network or function failures.

Family access is never granted from the local cache. If Supabase cannot verify
the current `family_members` row, the app shows a retry/sign-out screen.

Family invite URLs use iOS Universal Links in the form
`https://ninai.app/invite/<token>`. The backend issues 128-bit tokens, expires
them after seven days, limits each link to seven distinct acceptances, records
accepted Auth user IDs, and revokes the previous link when it is rotated.

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

## Deploy Nina chat

The local OpenAI key belongs only in `supabase/.env.local`, which is ignored by Git. Never add it to the iOS target or an xcconfig file.

After applying the latest migration, authenticate and deploy with the Supabase CLI:

```sh
npx supabase login
npx supabase secrets set --env-file supabase/.env.local --project-ref apemftmlsjocvifbptum
npx supabase functions deploy nina-chat --project-ref apemftmlsjocvifbptum --use-api
```

Deploy the account deletion function with the same Supabase secret configuration:

```sh
npx supabase functions deploy delete-account --project-ref apemftmlsjocvifbptum --use-api
```

`delete-account` must have access to `SUPABASE_SERVICE_ROLE_KEY` or
`SUPABASE_SECRET_KEYS` in Supabase function secrets. The iOS app calls it with
the user's JWT; the service role key must never be shipped in the app.

Interactive Nina chat uses `gpt-5.4-mini`. Model selection is fixed in the
function so a deployment environment override cannot silently change the
budget model or response behavior.

Household context required for each reply is sent from the Edge Function to OpenAI with API response storage disabled (`store: false`).

The OpenAI project must have API billing or credits enabled. A valid key without available quota will return `429 insufficient_quota`.

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
and deletes all fixtures. It never stores assistant replies or household
content in the report.

Keep `NINA_AI_V2_ENABLED = NO` for general builds until the test-account
rollout is approved. Enable it in the ignored local secrets xcconfig or the
release configuration used for the selected test accounts.

The database enforces the hard US$25 cap. Also set the OpenAI project
**Monthly budget** to US$25 under Platform **Project > Limits** as a secondary
soft alert; OpenAI project budgets do not stop API requests.

## Privacy launch artifacts

- Public privacy policy: `web/src/pages/privacidade.astro`
- App Store privacy labels: `docs/privacy/app-store-privacy-labels.md`
- LGPD posture checklist: `docs/privacy/lgpd-launch-posture.md`

Before production App Store submission, deploy `https://ninai.app/privacidade`
and confirm it includes the final legal entity and privacy contact.
