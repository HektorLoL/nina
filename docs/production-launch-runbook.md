# Nina Production Launch Runbook

Last updated: 2026-10-05

This is the release gate for Nina. A successful local build is not sufficient:
public launch requires the repository preflight, production configuration
preflight, deployed online checks, database tests, and TestFlight scenarios to
all pass for the same release candidate.

## 1. Repository gate

Run from the repository root:

```sh
npx deno task preflight:repo
```

This verifies release identity/version settings, StoreKit product identifiers,
Universal Links, the privacy manifest, ignored local configuration, tracked
credential patterns, protected local-data and erasure invariants, an app that
calls no sign-in but Apple's, legal-metadata wiring, the all-ages rules (no
string claims nothing is kept at the model provider, the Terms state the rating
and set no minimum age, `/familias/` and `/denuncia/` exist, the app and the
website show the same rating, the Declared Age Range and production App Attest
entitlements, iOS 26.4 on every configuration), and CI enforcement. It never
prints credential values.
CI runs the same gate on every pull request and push to `main`.

## 2. Prepare the release environment

Copy `config/production.env.example` to the ignored `config/production.env` and
replace every placeholder. Keep the file local. It is an inventory for
preflight, not a provider-specific upload file.

Distribute only the relevant values:

| Destination                    | Values                                                                                                                                                |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| iOS release xcconfig           | `NINA_SUPABASE_URL`, `NINA_SUPABASE_PUBLISHABLE_KEY`, `NINA_AI_V2_ENABLED`, `NINA_ATTACHMENTS_ENABLED`                                                                            |
| Cloudflare Worker runtime      | `NINA_SUPABASE_URL`, `NINA_SUPABASE_PUBLISHABLE_KEY`, `NINA_SUPABASE_SECRET_KEY`, `NINA_WAITLIST_HASH_SALT`                                           |
| Astro production build         | All `PUBLIC_NINA_*` values, including `PUBLIC_NINA_LEGAL_ENTITY_ADDRESS` and `PUBLIC_NINA_REPORT_CONTACT_EMAIL` (both new on 2026-09-29; the report address falls back to the privacy one) |
| Supabase Edge Function secrets | `OPENAI_API_KEY`, `NINA_APP_BUNDLE_ID`, `NINA_APP_APPLE_ID`, `NINA_PREMIUM_PRODUCT_IDS`, `NINA_APP_STORE_ONLINE_CHECKS` (and never `NINA_APP_STORE_ENVIRONMENT`, below), `NINA_APP_ATTEST_MODE=production`, `NINA_SAFETY_ID_SALT`, and the three `APPLE_SIGN_IN_*` values (below) |
| Operator machine only          | `NINA_RESEND_API_KEY` (sending-only), read by `deno task waitlist:send`                                                                               |
| Release records only           | `NINA_APPLE_TEAM_ID`, `NINA_PUBLIC_BASE_URL`, `NINA_CONTROLLER_DECISION_MAKERS` (the company's partners and administrators, comma-separated; `deployment.legal-launch-identity` fails if the encarregado is one of them or the list is missing) |

Do not upload the complete inventory to any one platform. In particular, never
place `NINA_SUPABASE_SECRET_KEY` or `OPENAI_API_KEY` in an Astro `PUBLIC_*`
variable, Xcode setting, app plist, or client bundle.

If this release is the first to set `NINA_AI_V2_ENABLED=YES`, section 3 carries a
one-time database step that must run before the archive is built.

Validate the inventory before deployment:

```sh
npx deno task preflight:production --env-file config/production.env
```

The command checks key roles without printing keys, requires an App Store
verifier that accepts production and sandbox, compares product/team/bundle
identifiers with source control, and fails on incomplete controller, DPO, or
mailbox values.

### App Store verifier: production, then sandbox

`NINA_APP_STORE_ENVIRONMENT` stays unset in production, at launch and after it.
The server then verifies a receipt as Production first and as Sandbox second,
and never as Xcode or Local Testing. App Review buys with the release build in
Apple's sandbox, so a server pinned to `production` refuses the reviewer's
purchase and the review fails under Guideline 2.1. Why a sandbox purchase on
the production server is safe, and what it costs, is in `docs/premium-flow.md`
§6. The inventory check `environment.app-store-mode` fails if the variable is
set to anything. Check the deployed secret too:

```sh
npx supabase secrets list --project-ref <project-ref> | grep NINA_APP_STORE_ENVIRONMENT
```

It must print nothing. If it prints a line, remove the secret; the functions
read it on the next request, with no redeploy:

```sh
npx supabase secrets unset NINA_APP_STORE_ENVIRONMENT --project-ref <project-ref>
```

Every sandbox purchase covers its buyer's house for free, and a public
TestFlight link reaches whoever it is forwarded to. Give that link a tester
limit and turn it off when the round of testing ends.

### Secrets the all-ages release adds

Three kinds of value are new on 2026-09-29. None of them belongs in the app, an
xcconfig, a `PUBLIC_*` variable, the repository, a chat or a log.

- **`NINA_SAFETY_ID_SALT`** (nina-chat). At least 32 random characters. Without
  it every chat turn answers `503 service_not_configured`, so set it before
  deploying nina-chat:

  ```sh
  npx supabase secrets set --project-ref apemftmlsjocvifbptum NINA_SAFETY_ID_SALT="$(openssl rand -hex 32)"
  ```

  Never rotate it casually: it keys OpenAI's `safety_identifier`, so a new salt
  makes every adult a new person to OpenAI's abuse monitoring.
- **`NINA_APP_ATTEST_MODE=production`** (age-signal). `development` and
  `insecure-local` are refused unless the project URL is loopback, and the
  production preflight's `deployment.app-attest-mode` fails on anything else.
- **The Sign in with Apple key, which only Heitor pastes.** `delete-account`
  revokes the person's Apple token after a deletion, signing its client secret
  with the `.p8` key made on 2026-09-28. The Team ID and Key ID are not secret;
  the key is. Paste it from the file, in Terminal, on the operator Mac:

  ```sh
  npx supabase secrets set --project-ref apemftmlsjocvifbptum \
    APPLE_SIGN_IN_TEAM_ID=97PL8KQA8L APPLE_SIGN_IN_KEY_ID=G558FXQWMN
  npx supabase secrets set --project-ref apemftmlsjocvifbptum \
    APPLE_SIGN_IN_PRIVATE_KEY="$(cat ~/Documents/AuthKey_G558FXQWMN.p8)"
  npx supabase secrets list --project-ref apemftmlsjocvifbptum | grep -E 'APPLE_SIGN_IN|NINA_SAFETY_ID_SALT|NINA_APP_ATTEST_MODE'
  ```

  The last command prints names and digests only; all five must appear. Keep
  the `.p8` file off the repository and back it up somewhere private: Apple lets
  you download it once. Without these secrets deletion still works — the Auth
  user, photos and data are gone — but every deletion logs
  `apple_token_revocation_failed` with stage `configuration`, and the person's
  "Sign in with Apple" link to Nina stays listed in their Apple Account until
  they remove it. That is the decided behaviour: a revocation failure never
  blocks, undoes or changes a deletion. After deploying, prove it once with a
  throwaway account: delete it in the app, then check the function log shows no
  `apple_token_revocation_failed` and that Settings › Apple Account › Sign in
  with Apple no longer lists Nina.

### Sign-in providers: Apple only

Nina signs in with Apple and nothing else. In Supabase → Authentication →
Sign In / Providers, keep **Apple** on (client ID `com.heitor.nina`) and turn
**Email** and every other provider off. Keep "Allow new users to sign up" on:
Apple is the door that creates accounts. Turning Email off is the one step the
repository cannot perform; do it once, before the first Apple-only build reaches
testers. If `com.heitor.nina://login-callback` was ever added under URL
Configuration → Redirect URLs, remove it. In Authentication → Emails → SMTP
Settings, turn custom SMTP off: since 2026-09-09 it holds a copy of the
sending-only Resend key, and email login was its only consumer. Turning it off
is what makes `NINA_RESEND_API_KEY` "Operator machine only", as the table above
says. Rotate the key only if that copy is thought exposed; if SMTP stays on,
record the copy as a Supabase Auth destination in the table instead.

```sh
curl -s -H "apikey: $NINA_SUPABASE_PUBLISHABLE_KEY" "$NINA_SUPABASE_URL/auth/v1/settings" | grep -oE '"(apple|email|google|phone)":[a-z]+|"passkeys_enabled":[a-z]+'
```

It must read `"apple":true` with `"email"`, `"google"`, `"phone"` and
`passkeys_enabled` all `false`. The online preflight checks the same answer
(`deployment.sign-in-providers`). With Email off, a TestFlight build of 7 or
earlier that still shows "Entrar com email" answers an address that has an
account with "Não foi possível entrar agora. Tente de novo." and a new address
with its own no-account line ("Esse email não tem conta. Continue com a Apple."
on build 7, "Esse email ainda não está vinculado a uma conta Nina." before it).
Either way no code is sent, and its Apple button keeps working. Build 7 also
carries a hidden "Continuar com o Google" row that appears if Google is ever
turned on, so keep Google off. Turning Email off most likely does not end
sessions that were already signed in by code; they last until that person signs
out.

**Allow users without an email (on since 2026-10-05).** In the same Apple
provider settings, "Allow users without an email" is on; Heitor turned it on
on 2026-10-05, before build 11 reached anyone. Since
build 11 the sign-in never asks Apple for the email (build 12 asks for the name
alone), so a new Apple ID's identity
token carries no email claim; with the switch off GoTrue refuses the account
as an unverified email, and every new person reads "Não foi possível entrar
agora. Tente de novo." It is backward-compatible with build 10, whose minor,
unknown and unreadable sign-ins already asked for no scope. `/auth/v1/settings`
does not report the switch, so no preflight can prove it; prove it on a device
instead: sign in with a brand-new Apple ID (or one that removed Nina under
Settings › Apple Account › Sign in with Apple) on build 12 and land on "Antes,
sua faixa de idade.". `supabase/config.toml` sets `email_optional = true` for
the local stack only.

### Deletion requests by mail

Since build 11, a deletion that is refused, or fails twice in a row (a
cancelled Apple sheet counts), offers "Para apagar mesmo assim, escreva para
privacidade@ninai.app." The mail carries the subject "Apagar minha conta" and
"Referência: ‹auth user id›", or, for a guardian, "Apagar a conta de um menor"
with "Referência: ‹ward's `family_members.id`›" and "Responsável: ‹the
guardian's own auth user id›". Accounts made since build 11 and minors have no
email, so the reference is how the account is found. **The reference proves nothing**:
every adult of a house can read every member's `user_id` and member id, and an
owner or admin also sees the ids on join requests, so a mail carrying only a
reference may come from someone else in the house. A deletion cannot be undone,
and deleting an owner hands the house to the remaining adult, so the id alone is
never enough. Answer within the 15 days the privacy policy promises:

1. **Find the account by the reference**, never by a name or an address:

   ```sql
   select id, email, created_at from auth.users where id = '<auth user id>';
   select id, user_id, family_id, household_role
     from public.family_members where id = '<ward member id>';
   ```

   No row means the account is already gone (a deletion whose answer was lost
   reads "A conta pode já ter sido apagada." in the app); say so and stop.
2. **Prove that the sender controls the account, from inside it.** Reply to the
   sender with a one-time code and nothing else about the account:

   ```sh
   openssl rand -hex 3
   ```

   and ask them to open Ajustes › Perfil, type that code as their name, save,
   and answer the mail. Only the signed-in account can write its own profile
   row (`profiles` policy "Users can update own profile"), so another adult who
   knows the id cannot pass this. Then read it back:

   ```sql
   select display_name, updated_at from public.profiles where id = '<auth user id>';
   ```

   It must equal the code exactly. A code is used once; a code that appeared in
   an earlier request is never accepted again.
3. **A guardian's request for a ward**: run step 2 on the guardian's own
   reference (the "Responsável" line), then check that this guardian may act for
   that ward today, with the same rule the app's guardian deletion uses:

   ```sql
   select public.authorize_guardian_account_deletion('<guardian auth user id>', '<ward member id>');
   ```

   It returns the ward's auth user id, or raises `guardian_access_denied`; stop
   on the error. The guardian can also delete the ward in the app (Casa › the
   ward's screen › Apagar conta), which needs none of this.
4. **A minor's or an unknown-age account's own request** cannot pass step 2:
   those accounts have no Perfil editor, and nothing new is asked of a minor.
   Never delete one on the reference alone. If it has a live guardian, answer
   that the guardian can delete it in the app or write in under step 3. If it is
   a minor with no house and no pending request, `nina-maintenance` deletes it
   30 days after its last house, request or decision; say so. Otherwise (an
   unknown-age account with no house) the in-app "Apagar conta" is the only
   proven path: find why it fails (the `delete-account` logs carry the request
   id and a stable code), fix it, and ask the person to try again.
5. **Delete in the same order the app does**: storage
   `profile-photos/<uid>/*` first, then the Auth user in Authentication › Users.
   The `BEFORE DELETE` trigger on `auth.users` runs `prepare_account_deletion`
   itself, so the house, memberships and authored data follow the same rules as
   an in-app deletion. The person's Apple token is not revoked on this path
   (there is no authorization code); say so in the answer.
6. **Record** the date, the reference, which proof passed (step 2 or 3) and the
   outcome in the request log (`docs/privacy/lgpd-launch-posture.md`), and
   answer the person. Keep no copy of the code beyond the thread.

## 3. Database and Edge Functions

Run the local gate first — `docs/local-database.md` — so a migration that cannot
apply from empty is caught on the machine rather than against a shared project.

Then use a separate staging Supabase project. Apply migrations in order, and
run:

```sh
npx supabase db lint --linked --fail-on error
npx supabase test db --linked
```

Deploy `nina-chat`, `nina-maintenance`, `delete-account`,
`premium-subscription-sync`, `app-store-server-notifications` and `age-signal`.
Schedule `nina-maintenance` daily and alert on timeout, non-2xx response, or
missed run. The all-ages release has its own order, below; follow it rather
than this generic one on that day.

Before production, prove:

- account deletion removes the Auth user, profile photos, authored Nina data,
  memberships, and solo homes;
- deleting a shared-home owner promotes a deterministic replacement, preserves
  shared records without the deleted identifier, and revokes/transfers active
  invitations;
- a late restrictive family or invite row cannot block Auth deletion, and a
  retry after a transient failure is idempotent;
- every household table remains isolated by RLS;
- the AI budget and retention jobs enforce their hard limits;
- Apple's Notifications V2 test returns `200` and is persisted;
- a TestFlight purchase is recorded with `environment = 'Sandbox'` and covers
  the buyer's house, which is how App Review's purchase will arrive;
- subscription purchase, restore, renewal, expiration, cancellation, and
  billing-retry states synchronize correctly;
- a minor account reads 0 rows from every household table and sees only its own
  tasks, without a detail line; an unknown-age account cannot create a house;
- a guardian approval writes the member, profile, guardianship, consent and
  acceptance together, and a guardian deletion of a claimed minor runs photos →
  database → Auth like any other;
- a deletion with a fresh Apple authorization code revokes the Apple token, and
  a deletion without one still completes.

For the deletion staging exercise, use accounts created only for the test. Run
the in-app flow with a solo owner and with a shared-home owner, then verify the
Auth user and `profile-photos/<user-id>` objects are gone. Verify the shared
home has a remaining owner, no invite retains the deleted UUID, and shared
records that survive have nullable creator references cleared. Function failure
logs may contain the request ID and stage only, never the user ID, bearer token,
request body, or raw upstream error.

### The all-ages release, in order (one day)

The eight migrations `202609290001`–`202609290008` and build 10 change what every
account may do, so they go out together, in this order. Run the local gate
first (`deno task db:reset && deno task db:test`, 657 assertions on
2026-09-29).

0. **Before the day, make build 10 ready without sending it to anyone.** Build
   10 is the first to carry `com.apple.developer.declared-age-range` and
   `appattest-environment = production`. In Certificates, Identifiers & Profiles
   → Identifiers → `com.heitor.nina`, enable Declared Age Range and App Attest,
   and request them if the portal lists either as request-only (whether Apple
   must approve them is UNVERIFIED); or confirm that automatic signing with
   `-allowProvisioningUpdates` added both. Turn automatic distribution off on
   every internal tester group. Archive build 10 (§5) from the committed
   revision, run the `--ios-artifact` gate on it, upload it and wait until
   TestFlight finishes processing. If signing, provisioning or processing fails
   here, stop: nothing has changed yet, and builds 1–9 still work against the
   old schema.
1. **Expire every TestFlight build up to 9** in App Store Connect → TestFlight →
   iOS builds → each build → Expire. Those builds have no age step: after the
   migrations their users read as unknown, cannot grant the new AI consent
   (they send no transfer consent) and cannot approve a minor, and a build of 7
   or earlier still offers an email door. Expiring first means nobody meets a
   half-working app.
2. **Apply the eight migrations in filename order**, nothing else in between:

   ```sh
   npx supabase db push --project-ref apemftmlsjocvifbptum --dry-run
   npx supabase db push --project-ref apemftmlsjocvifbptum
   ```

   The dry run must list exactly `202609290001_age_assurance` through
   `202609290008_reports_holds_export_retention`. Applying one through the
   Supabase MCP `apply_migration` records a 14-digit version instead of the
   filename's; repair it as `CLAUDE.md` §12 says. After `…0003` every account
   without an age row reads the minimized minor shape, and `…0006` withdraws
   every live AI consent with `policy_changed` — both intended.
3. **Set the secrets** above (`NINA_SAFETY_ID_SALT`, `NINA_APP_ATTEST_MODE`, the
   three `APPLE_SIGN_IN_*`).
4. **Deploy the functions**, `age-signal` first:

   ```sh
   for fn in age-signal nina-chat nina-maintenance delete-account premium-subscription-sync app-store-server-notifications; do
     npx supabase functions deploy "$fn" --project-ref apemftmlsjocvifbptum --use-api
   done
   ```

   `app-store-server-notifications` now checks the same buyer eligibility as
   the sync path before a new original becomes a subscription, so it is
   redeployed too. Then compare `list_edge_functions` versions and dates with
   `git log`.
5. **Set the date legacy child profiles expire.** A child profile created before
   today has no guardian consent; it shows "Sem autorização" and is deleted on
   this date unless a guardian answers "Sou responsável":

   ```sql
   update private.age_policy set legacy_profile_deadline = now() + interval '30 days' where singleton;
   ```

6. **Mark the tester accounts.** App Attest and Declared Age Range do not run on
   the Simulator, and a tester whose phone has not yet shared a band reads as
   unknown. In the SQL editor, for each tester who is an adult (their Auth user
   id from Authentication → Users):

   ```sql
   select private.operator_set_age_status('<auth user id>', 'adult', null, true, 'testflight');
   ```

   The record carries assurance `operator`, so it counts as trusted. Leave at
   least one tester unmarked on a real iPhone, so the Apple path is proven.
7. **Distribute build 10**, the one step 0 uploaded and processed, to the
   tester groups, and turn automatic distribution back on if you want it. An
   external group (the public link) gets it only after Beta App Review, which
   starts when the build is added to that group and can take a day; submit it
   only after step 6, because the reviewer uses production. External testers
   have no working build until the review passes. The reviewer signs in with
   their own Apple ID and starts at unknown age, so the Test Information must say
   what they will see.
8. **Read the result the next morning** with the queries in "Measuring the age
   distribution on TestFlight" below, and check the nina-maintenance response
   (`minor_accounts`) and log for `minor_account_deletion_failed` and retention
   errors.

Skipping step 1 or shipping build 10 before step 2 is the dangerous order: build
10 reads a home context without `viewer_kind` as a minor's, so against the old
schema every adult would see the minor screen.

### What testers will notice

- **Everyone accepts the AI notice again.** The old notice said nothing sent to
  OpenAI was kept; OpenAI keeps abuse logs up to 30 days, so those consents were
  given on untrue text (LGPD art. 9 §1). The chat shows "Este aviso mudou." over
  the new card, which names OpenAI and the house details, and "Aceitar e
  conversar com a Nina" stays grey until the separate "Envio para fora do
  Brasil" box is ticked. Until two adults of a house accept again, that house
  gets no weekly insight.
- **One Apple button, and Apple asks only for the name** (build 12; build 11
  asked for nothing). The welcome shows only "Continuar com a Apple"; Apple's
  sheet offers to share the name and never asks for the email, and the age step
  comes right after it. Nina keeps the first name alone, on the phone until the
  person is named; the sign-in sends no name to the server. An adult who shared
  a name goes straight to creating or joining a house and is named by it there;
  only one who blanked it, or whose Apple ID already authorized Nina, types a
  first name there. A minor, or anyone whose age Apple has not shared, confirms
  a first name beside the invite, prefilled with Apple's. A declared
  (not Apple-confirmed) adult keeps
  the house but sees "A conversa pede idade confirmada." instead of the chat,
  and no paywall.
- **Children's profiles need a guardian.** An existing child profile reads "Sem
  autorização" until an Apple-confirmed adult taps "Sou responsável"; its
  "Mostrar" list is off until then.
- **iOS 26.4 or later.** Build 10 does not install on older iPhones.

### Measuring the age distribution on TestFlight (decision D3)

D3 keeps chat, Premium, child profiles and approving a minor for Apple-confirmed
adults, and lets Heitor admit self-declared adults to chat and Premium later.
Measure before deciding. Nina records only a status, a band, how Apple obtained
it and a parental-controls flag — never a birth date or the range's bounds —
and the counts come from one operator function:

```sql
select * from private.age_assurance_distribution();
```

Read it after each TestFlight round. What each row means:

- `adult` / `confirmed` — Apple confirmed 18+ (a `.confirmed` declaration on
  iOS 26.5, or an ID, payment or other check). Trusted.
- `adult` / `self_declared` — the person or their Apple Account said 18+
  without a check. Runs a house; no chat, no Premium, never acts for a minor.
- `adult` / `operator` — marked by Heitor in step 6. Trusted; not evidence of
  how real users come back, so leave these out when reading the ratio.
- `minor` / any — Apple (or a guardian's lower band) says under 18.
- `unknown` / `none` — declined to share, Apple did not answer, or App Attest
  failed. Treated as the youngest band.
- `parental_controls_active = true` — never trusted, whatever the assurance.

If most real adults come back `self_declared`, chat and Premium are unusable for
them. To admit them to chat and Premium only (acting for a minor stays
confirmed-or-operator in the SQL, whatever this row says):

```sql
update private.age_policy set trusted_assurances = '{confirmed,operator,self_declared}' where singleton;
```

Change Terms §4 and privacy §5 in the same release, since both say Apple must
confirm the age (`docs/privacy/lgpd-launch-posture.md`). Revert with
`'{confirmed,operator}'`; the policy row can never drop those two.

### Age contests and child-safety holds

An age contest (Decreto 12.880 art. 27) follows `docs/age-contest-runbook.md`; a
child-safety hold follows `docs/child-safety-runbook.md`. Both are operator
steps in the SQL editor, never client features.

### Close out pending proposals before enabling the AI flag

`NINA_AI_V2_ENABLED` is a client flag with no server counterpart: `nina-chat`
writes a `nina_proposals` row on every turn whether or not the flag is on, and
those rows stay `pending` until retention rejects them at 30 days. So the first
build shipped with `YES` surfaces up to 30 days of accumulated proposals at once
as live confirmation cards, and confirming one creates a task the household has
been living with for weeks.

Run this once against production in the Supabase dashboard SQL editor, after the
decision to flip the flag and before archiving the build that carries it. It is a
one-time data decision rather than schema, which is why it is not a migration:

```sql
update public.nina_proposals
set state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'v2_rollout')
where state = 'pending';
```

Confirm it took effect with `select count(*) from public.nina_proposals where
state = 'pending';`, which must read `0` at that moment. It closes proposals the
app never showed anyone, so nothing a user acted on is lost; rows created after
this point belong to turns whose users will actually see the cards.

Skipping it ships an inbox pre-loaded with stale, already-satisfied work on first
launch. Running it after that build is public does not undo the duplicate tasks
users have already confirmed.

## 4. Website deployment

Provide the `PUBLIC_NINA_*` values to the Astro build environment — eight
since 2026-09-29, with the controller address and the report mailbox. Build
before deploying so `/privacidade` contains the final controller and DPO
identity. Configure the Worker public values and its two secrets separately.

Decision D2 (2026-09-29): a company with a CNPJ, its address and an encarregado
who is not the controller exist before launch. Until then today's values stay:
the page reads `data-legal-status="complete"` and `data-legal-launch="pending"`,
and the production preflight's `deployment.legal-launch-identity` fails. That one
failure is expected on a TestFlight gate and blocks App Store submission. On the
day the company exists, change the five legal values and the address in the
Cloudflare build variables and `config/production.env`, rebuild, and check the
privacy page reads `data-legal-launch="ready"`.

`PUBLIC_NINA_APP_STORE_ID` is read at build time, exactly like the legal
identity. Until it holds the numeric App Store ID, `/invite/` hides the install
badge and offers the waitlist instead. Once the app exists in App Store Connect,
set the variable, then rebuild and redeploy the website — a Cloudflare variable
change alone leaves the install path hidden forever, and every invited person
keeps landing on a page that cannot get them the app.

The waitlist hears from Nina exactly once, after the app is live and the site
above is rebuilt with the store id. From the repository root, with
`config/production.env` holding the Resend key and the numeric store id:

```sh
npx deno task waitlist:send --campaign lancamento-2026 --dry-run
npx deno task waitlist:send --campaign lancamento-2026
```

The dry run prints only a count. The real run reads the subscribed rows at that
instant, sends one message per address, records each delivery, and can be
rerun after a failure without repeating anyone. `web/README.md` has the test
send.

After Cloudflare deploys `https://ninai.app`, run:

```sh
npx deno task preflight:production --env-file config/production.env --online
```

Online mode performs read-only probes of the landing page, security headers,
`/api/health`, privacy metadata, unsubscribe indexing policy, the AASA file, and
the Supabase Auth provider list (Apple on, every other door off).
`/api/health` in turn probes the public invite RPC and the service-only current
waitlist schema contract with bounded requests. All checks must pass. A `503`
health response is a release blocker, even when the environment variables look
correct.

## 5. Distribution gate

Archive the exact source revision that passed the gates. Confirm that the
archive's generated plist contains a root HTTPS Supabase URL, a publishable key,
the intended AI flag, bundle ID, version, and build number. It must not contain
a Supabase secret/service-role key or OpenAI key.

Run the gate against the final archive before upload:

```sh
npx deno task preflight:production \
  --env-file config/production.env \
  --online \
  --ios-artifact /absolute/path/to/Nina.xcarchive
```

Artifact mode decodes the generated app plist, requires the bundled privacy
manifest, compares every public release value with the approved inventory, scans
the complete app payload for high-confidence server credentials, and checks the
archive signing team and identity. A direct `.app` can be used during
development, but produces a warning because it cannot prove archive signing.

### Uploading a TestFlight build from the command line

Raise `CURRENT_PROJECT_VERSION` above every build App Store Connect has seen,
commit, push, then archive the pushed revision:

```sh
xcodebuild archive -project Nina.xcodeproj -scheme Nina -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /absolute/path/to/Nina.xcarchive
```

Run the artifact gate above against that archive. Then write the export options
once and upload:

```sh
cat > /absolute/path/to/ExportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>97PL8KQA8L</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath /absolute/path/to/Nina.xcarchive \
  -exportOptionsPlist /absolute/path/to/ExportOptions.plist \
  -exportPath /absolute/path/to/export -allowProvisioningUpdates
```

`Upload succeeded` and `EXPORT SUCCEEDED` mean App Store Connect has the build
and is processing it. This Mac holds only an Apple Development identity: the
export re-signs through Xcode's cloud-managed distribution certificate with the
Apple ID signed in to Xcode, so a missing or expired Xcode login fails here, not
at archive time. `manageAppVersionAndBuildNumber` is off so the uploaded build
number is the committed one. Tag the revision `testflight-1.0-<build>` and move
the archive to `~/Library/Developer/Xcode/Archives/` so the Organizer keeps it.
Build 6 was uploaded this way on 2026-09-25.

Run the release candidate through TestFlight on at least one current iPhone and
one supported older device. Exercise:

- first launch, Apple sign-in with a brand-new Apple ID (no email reaches Nina:
  the Ajustes account row is the name alone; with the name shared, creating or
  joining a house shows no name field, also after force-quitting the app
  between Apple's sheet and the house, and the member reads the first name
  only, never the family name; with the name blanked in Apple's sheet, "Seu
  primeiro nome" appears there) and with a pre-build-11 account (keeps its email,
  including one hidden behind Apple's private relay), sign-out, and session
  restoration;
- home creation, invitation acceptance/revocation/expiry, and member removal;
- task/reminder recurrence, notifications, offline edits, and conflict repair;
- Nina consent, attachments, proposal confirmation, privacy export, history
  deletion, and account deletion;
- upgrade from the previous public build with populated offline household,
  profile/photo, consent, and pending-invite data; verify the data survives the
  protected-cache migration and the legacy defaults entries disappear;
- generate a privacy export, verify account/profile/photo/consent/home data are
  represented, dismiss the export view, relaunch, and verify no stale export
  remains in the app's temporary container;
- begin a home or profile refresh on a constrained connection, delete the
  account before it completes, then verify late responses do not restore UI
  state or recreate local files;
- Dynamic Type, VoiceOver, Reduce Motion, light/dark appearance, and denied
  notification/photo permissions;
- StoreKit purchase, restore, family/account changes, cancellation, expiration,
  retry, and server-notification delay;
- the age matrix, on devices only (the Simulator runs neither Declared Age Range
  nor App Attest): Apple's age-assurance sandbox on iOS 26.4+ (Settings ›
  Developer › Sandbox Apple Account › Manage › Age Assurance) for every case;
  real Brazilian accounts — an Apple-confirmed adult, a self-declared adult, a
  16–17 and a 13–15 Family Sharing child, an under-13; Sign in with Apple for a
  minor (Apple's given name only prefills "Seu primeiro nome" beside the
  invite); whether a recheck shows Apple's sheet; a decline and a
  later share; a guardian approval, supervision change and guardian deletion end
  to end; the minor's daily limit; a notification on a minor's phone ("‹título›
  · ‹hora›", silent at night);
- account deletion by a subscriber (the "Sua assinatura continua." card and
  "Gerenciar assinatura"), by a person with no house, and with the Apple token
  revoked; one real Apple-account deletion against delete-account v7; in
  airplane mode it reads "Sem internet. Nada foi apagado." and a second failure
  shows "Para apagar mesmo assim, escreva para privacidade@ninai.app."; a
  cancelled Apple sheet sends nothing and reads "A Apple não confirmou. Nada foi
  apagado.", and a second cancellation adds the same mail line; the "Antes, sua
  faixa de idade." prompt carries "Sair da conta" and "Apagar conta";
- the welcome and the startup screen show the rating mark in the same spot, and
  no other screen (settings, the app switcher) shows it; the "Só um instante."
  wait is centred with a round disc.

Record the tested build number, devices, OS versions, tester, date, and result.
Do not promote a different build number without rerunning the affected gates.

For the same release build, inspect a development-signed app container on a
physical device after first unlock. Confirm private-cache and privacy-export
files have `NSFileProtectionCompleteUntilFirstUserAuthentication`, use opaque
names, enforce the documented size bounds, and carry the backup-exclusion
resource flag. Simulator tests may verify writes and backup exclusion, but do
not treat missing simulator file-protection metadata as physical-device proof.

## 6. App Review and ClassInd, before submitting

Answer Apple's age questionnaire only after the all-ages release is live. The
answers, the rationale per item and the review note are in
`docs/privacy/classificacao-indicativa.md`; keep the written rationale there
(Guideline 2.3.6).

1. **Ask the four questions in writing, in the App Review notes of the
   submission** (decided 2026-09-29). Apple answers in the submission's
   messages in App Store Connect; a disagreement costs one rejection round, and
   D1 already accepts a 10 or 12. The App Review page cannot start a
   conversation without a submission (checked 2026-09-29), and the "Contact us"
   form is for rejections. A free 30-minute App Review appointment (Meet with
   Apple, Tuesdays and Thursdays:
   `https://developer.apple.com/events/view/upcoming-events?search=Review`)
   gets the answers before submitting, if that ever matters more than the call.
   The four questions, word for word:
   1. Does content shared inside a closed household of up to 8 approved people
      count as User-Generated Content or as Messaging?
   2. Do features that the server gates to users the Declared Age Range API
      confirms as 18+ count toward the questionnaire answers?
   3. Does "some features are only for adults" in the Terms count as a minimum
      age requirement?
   4. Sign in with Apple is the only sign-in, and the chat and the subscription
      open only for an adult whose age Apple confirmed. How should the reviewer
      reach those features?

   Record the answers in the rating document. The first submission carries the
   "Livre" (AL) answers with these questions beside them in the notes, so the
   reviewer sees both at once. If the answers push the rating to 10 or 12, keep the
   chat (D1) and change `NinaRating.currentCode`, `web/src/rating.ts` and the
   Terms together; `repository.rating-constant-consistency` fails until they
   agree.

   The notes also carry this paragraph about Sign in with Apple, word for word
   (Guideline 4.0 has refused apps that ask for a name after Sign in with Apple;
   decided 2026-10-05, build 12):

   > Sign in with Apple is the only way in. Nina requests only the full-name
   > scope and never the email scope, and keeps only the first (given) name
   > Apple shares; it never stores the family name, and it never asks for an
   > email address, so an account created with this version holds none. The
   > first name is what the other members of the household see. An adult is
   > asked to type a first name only when Apple shared none (the person chose
   > not to share it, or the Apple ID had already signed in to Nina, since
   > Apple shares the name only on the first sign-in), and only when creating
   > or joining a household. A person under 18, or anyone whose age Apple has
   > not shared (Nina treats that account as a minor's until it does), confirms
   > a first name, filled in from Apple's when shared, only when asking a
   > guardian to let them join a household.
2. **Age Suitability URL:** `https://ninai.app/familias/`. Made for Kids: No.
   Override to a higher rating: none — the Terms set no minimum age.
3. **Metadata:** no "para crianças" in the name, subtitle, icon, screenshots or
   description, and screenshots that suit every age. The listing is "Nina:
   rotina da casa" since 2026-10-05; the old name said "amiga".
4. **ClassInd (MJSP):** self-classify against Portaria 1.048 and the Guia
   Prático, map each feature to its tendency and the on-by-default attenuator,
   and file the voluntary análise prévia (Portaria art. 46) as soon as build 10
   is feature-complete. The procedure, cost and required identity are
   UNVERIFIED; the company from D2 may be needed to file.
5. **Before release, read from the official source and correct if needed:** the
   ClassInd pictogram artwork and colours (gov.br/mj; `Nina/Theme.swift` and
   `web/src/rating.ts`), the CVV number 188 (cvv.org.br; `MinorViews.swift`,
   `/familias/`, the prompt), the Polícia Federal intake for child-safety
   reports (`docs/child-safety-runbook.md`), the OpenAI sub-processor link
   (`privacidade.astro`), Apple's App Attestation Root CA (compare with the
   embedded copy in `_shared/app-attest.ts`), and the 190 and Disque 100 numbers
   on `/denuncia/`.

## 7. Human approvals

The technical gate cannot substitute for these approvals:

- Heitor approves the new wording (consent v2, the guardian sheets, the minor
  screens, Terms, Privacy, `/familias/`, `/denuncia/`); no lawyer reviews it,
  so every Law-text-gated line cites its article in
  `docs/privacy/avaliacao-impacto-criancas.md` §9.
- D2: the company, its CNPJ and address, and a named encarregado who is not
  Heitor.
- Brazilian counsel, if engaged, approves the policy, legal bases,
  child/sensitive-data wording, controller identity, and DPO details.
- The privacy mailbox has a named owner and a tested response procedure.
- App Store privacy labels match the submitted binary and production operators.
- Transactional email has SPF, DKIM, DMARC, consent-at-send filtering, the Nina
  unsubscribe fragment link, and provider-side suppression synchronization.
- On-call ownership exists for website health, Edge Functions, database
  maintenance, subscription notifications, AI budget, and crash diagnostics.
