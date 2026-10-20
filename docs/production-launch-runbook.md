# Nina Production Launch Runbook

Last updated: 2026-10-20

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
entitlements, iOS 26.4 on every configuration), no iCloud conflict copy (a
`… 2.ext` file or a `… 2` folder) anywhere in the working tree outside
`node_modules` and `.git` (`repository.icloud-conflict-copies`, since
2026-10-19), and CI enforcement. It never prints credential values.
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
   outcome in the request log, and answer the person. Keep no copy of the code
   beyond the thread. **The request log is kept privately, never in this
   repository**, which is public on GitHub: in Heitor's private notes or a
   private spreadsheet, never in `docs/`, a commit, an issue, a pull request or
   a chat with an agent. What it holds is listed in
   `docs/privacy/lgpd-launch-posture.md` ("Recommended request handling"); an
   account reference is personal data even without a name.

### OpenAI dashboard

`OPENAI_API_KEY` reaches OpenAI from `nina-chat` and `nina-maintenance` only.
Check the account at platform.openai.com before launch and after any change to
it. The dashboard renames its pages; where a label below no longer matches,
record what it is called now (the labels are UNVERIFIED as of 2026-10-19).

- [ ] **One project for production.** `OPENAI_API_KEY` in the Edge Function
  secrets is a key of a project used by nothing else. The local eval's key
  (`supabase/.env.local`) belongs to another project, so revoking one never
  stops the other, and the eval's spend never reads as production's.
- [ ] **A restricted key.** It may call `/v1/responses` (with
  `/v1/responses/input_tokens`) and `/v1/moderations`, and nothing that writes
  files, fine-tunes, or manages the organization. After any change, send one
  chat turn on a test account: a key that refuses one endpoint fails every turn.
- [ ] **Models.** If the project limits models, it allows `gpt-6-luna`,
  `gpt-5.4-mini` (the insight's fallback) and `omni-moderation-latest`.
- [ ] **No training on Nina's data.** Organization › Data controls: sharing
  inputs and outputs with OpenAI is off, with no free-token programme. The
  privacy policy says OpenAI does not train on what Nina sends.
- [ ] **Nothing stored beyond abuse monitoring.** Every call sends `store:
  false`, so the project's logs of responses show no Nina conversation. Zero
  Data Retention is not on and is not claimed anywhere: the privacy policy
  publishes OpenAI's abuse logs of up to 30 days, and claiming less fails
  `repository.retention-claims`.
- [ ] **A monthly budget above the database's caps.** The database refuses a
  turn at its own caps (`private.nina_ai_budget_settings`: US$50 chat and
  US$10 insight since Heitor's choice 5 of 2026-10-19; §3, "The AI budget of
  19 October"). Set the project's monthly budget
  a little above their sum, with an email alert at the sum, so the database
  binds first and the dashboard is the backstop for an accounting bug. Whether
  the project budget stops requests or only alerts is UNVERIFIED; read it there.
- [ ] **Billing.** Enough prepaid credit for a month at the caps, or automatic
  recharge with a monthly ceiling. An empty balance fails every turn and every
  insight, whatever the database allows.
- [ ] **Rate-limit tier.** The Limits page lists all three models with room for
  the house ceiling (100 messages per house per day).
- [ ] **People.** Heitor is the only member, with two-factor sign-in on.
- [ ] **Data Processing Addendum** accepted for the organization (LGPD art. 39:
  the operator follows the controller's instructions). Record the date in the
  private records, not here. Where the dashboard offers it is UNVERIFIED.
- [ ] **The month's spend agrees with the database.** The Usage page for the
  production project should be close to what the database booked:

  ```sql
  select month_start, purpose, cap_microusd / 1e6 as cap_usd,
         spent_microusd / 1e6 as spent_usd, reserved_microusd / 1e6 as reserved_usd
  from public.nina_ai_budget_months
  order by month_start desc, purpose
  limit 4;
  ```

  OpenAI's figure well above `spent_usd` means a cost the accounting misses
  (an unpriced token kind, a call outside the reservation); stop and find it
  before the month ends.

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
  and no paywall. Since D3 (2026-10-14, below) a self-declared adult chats and
  can buy Premium once production holds the new policy row.
- **Children's profiles need a guardian.** An existing child profile reads "Sem
  autorização" until an Apple-confirmed adult taps "Sou responsável"; its
  "Mostrar" list is off until then.
- **iOS 26.4 or later.** Build 10 does not install on older iPhones.

### Measuring the age distribution on TestFlight (decision D3)

**Decided 2026-10-14: self-declared adults chat and buy Premium.** The
all-ages release kept chat, Premium, child profiles and approving a minor for
Apple-confirmed adults. On 2026-10-14 Heitor's own Brazilian adult account
still read `self_declared` on every retry, and Apple does not confirm adult
ages in Brazil, so no real adult could chat or buy. The reasoning, the legal
reading and the rating cost are in `docs/privacy/lgpd-launch-posture.md`,
"Decision D3". Acting for a minor stays confirmed-or-operator in
`private.is_trusted_adult`, whatever the policy row says, and active parental
controls still mean not trusted.

Nina records only a status, a band, how Apple obtained it and a
parental-controls flag — never a birth date or the range's bounds — and the
counts come from one operator function:

```sql
select * from private.age_assurance_distribution();
```

Read it after each TestFlight round. What each row means:

- `adult` / `confirmed` — Apple confirmed 18+ (a `.confirmed` declaration on
  iOS 26.5, or an ID, payment or other check). Trusted for everything.
- `adult` / `self_declared` — the person or their Apple Account said 18+
  without a check. Since D3: runs a house, chats after accepting the notice and
  buys Premium; never acts for a minor.
- `adult` / `operator` — marked by Heitor in step 6. Trusted; not evidence of
  how real users come back, so leave these out when reading the ratio.
- `minor` / any — Apple (or a guardian's lower band) says under 18.
- `unknown` / `none` — declined to share, Apple did not answer, or App Attest
  failed. Treated as the youngest band.
- `parental_controls_active = true` — never trusted, whatever the assurance.

**Apply it once in production**, from the SQL editor, in the same release as
the website that says so (Terms §4, privacy §3A and §5, `/familias/`,
`/suporte/`):

```sql
update private.age_policy set trusted_assurances = '{confirmed,operator,self_declared}' where singleton;
```

**Read it back.** The row must list the three assurances, and a
self-declared adult must read as allowed to use the AI and buy but not to act
for a minor:

```sql
select trusted_assurances from private.age_policy where singleton;

select private.may_use_ai('<self-declared adult auth user id>') as may_use_ai,
       private.is_trusted_adult('<same id>') as acts_for_minors;
```

Expect `{confirmed,operator,self_declared}`, then `true` and `false`. A
`false` in `may_use_ai` means the update did not land or that account has
active parental controls.

Ran on 2026-10-14, right after the push that published the pages: the row read
`{confirmed,operator,self_declared}`, and Heitor's self-declared account read
`may_use_ai` true, `premium_buyer_is_eligible` true and `is_trusted_adult`
false.

**What testers now see.** A self-declared adult who refreshes the house (pull
or return to the app) gets the consent card where "A conversa pede idade
confirmada." was, chats once they accept the notice and its transfer box, sees
Premium in Ajustes (and "Ver o Premium" when the day's messages run out), and
counts toward the weekly summary once they accept. The tour lands them on Nina. They still
cannot approve a minor ("Isso pede idade confirmada pela Apple.") or add or
answer for a child or teen ("Só um responsável com idade confirmada pela Apple
cadastra."). Build 12's in-app FAQ still asks
"Por que a conversa pede idade confirmada?" until people update to the next
build. The Terms version does not change, so nobody sees "Os Termos mudaram.".

**Revert** with `'{confirmed,operator}'`; the policy row can never drop those
two. A revert makes the pages above untrue again, so they change back in the
same release.

### Deleting a house, and the Terms of 15 October (`202610150001`)

Migration `202610150001_delete_family.sql` lets the titular delete the house
(`delete_family`), routes every house deletion through
`private.delete_household`, keeps each adult's AI consent as withdrawn proof
when a house goes, and copies a reply still held for review onto its report.
Build 14 never calls the new RPC and ignores the new `house_deleted` key, so
the migration may go first. Terms §5 says the titular may now delete the
house, and Heitor decided on 2026-10-15 that the recorded Terms version follows
the date the Terms page shows, so the version moves once that page is live.
Run the steps in this order, on one day.

1. **Local gate.** From a clean export (`git archive` of the commit, `CLAUDE.md`
   §12), `deno task db:reset && deno task db:test`.
2. **Pre-check, read only, in the SQL editor.** Production must still run the
   bodies the migration replaces:

   ```sql
   select routines.oid::regprocedure, md5(routines.prosrc)
   from pg_proc as routines
   join pg_namespace as namespaces on namespaces.oid = routines.pronamespace
   where (namespaces.nspname, routines.proname) in (
     ('public', 'get_family_access_decision'),
     ('public', 'prepare_account_deletion'),
     ('private', 'preserve_child_safety_account'),
     ('public', 'run_nina_retention'),
     ('public', 'delete_family'),
     ('private', 'delete_household'),
     ('private', 'settle_household_ai_runs')
   )
   order by 1;

   select confdeltype from pg_constraint
   where conname = 'nina_ai_consents_family_id_fkey';

   select table_schema, table_name, column_name
   from information_schema.columns
   where (table_schema, table_name, column_name) in (
     ('public', 'family_access_decisions', 'house_deleted'),
     ('private', 'nina_reply_reports', 'reply_text'),
     ('private', 'nina_reply_reports', 'request_text')
   );

   select max(version) from supabase_migrations.schema_migrations;
   select current_terms_version from private.age_policy;
   ```

   Expect exactly four functions: `get_family_access_decision()`
   `9dff4d97109e91ac13123982f9c59398`, `prepare_account_deletion(uuid)`
   `d61cf299c129e8a081c513112494cab1`,
   `private.preserve_child_safety_account(uuid)`
   `5db1706b597dfd828b725c658df2dc55` and `run_nina_retention()`
   `4f0def6c5524d14f3eeb10d8ef087431`; then `c` (cascade), no column rows,
   `202610140001` and `2026-09-29`. Any other body means production drifted
   from the repository: stop and compare before applying.
3. **Apply the migration**, either with `npx supabase db push` from the clean
   export (the dry run must list only `202610150001_delete_family`) or through
   the Supabase MCP `apply_migration` named `delete_family` with the file's
   body. The MCP records a 14-digit version, so repair it at once:

   ```sql
   update supabase_migrations.schema_migrations
   set version = '202610150001'
   where name = 'delete_family'
     and version <> '202610150001';
   ```

4. **Read back.** Rerun the first query of step 2. Expect seven functions:
   `get_family_access_decision()` `68a94e31814cf956b285f793cecd4b2d`,
   `prepare_account_deletion(uuid)` `9a956015a0ae0fd7dafc4f63db6c9348`,
   `private.preserve_child_safety_account(uuid)`
   `012635590a2240b8ad04e3e592c69ac8`, `run_nina_retention()`
   `45b9504c349019282403b680102cb5e4`, `delete_family(uuid, text)`
   `9723c67ffb8e8fa013d2e0f0ade44280`, `private.delete_household(uuid, uuid)`
   `f7b1d6693303b3e3a3bde61070efdf50` and
   `private.settle_household_ai_runs(uuid)`
   `b40485125ad32a93f118120bab887d2b`. Then:

   ```sql
   select
     has_function_privilege('authenticated', 'public.delete_family(uuid, text)', 'execute'),
     has_function_privilege('anon', 'public.delete_family(uuid, text)', 'execute'),
     has_function_privilege('service_role', 'public.delete_family(uuid, text)', 'execute'),
     has_function_privilege('authenticated', 'private.delete_household(uuid, uuid)', 'execute'),
     has_function_privilege('service_role', 'private.delete_household(uuid, uuid)', 'execute');

   select grantee, count(*)
   from (values ('authenticated'), ('service_role')) as roles(grantee),
     pg_proc as routines
   where routines.pronamespace = 'public'::regnamespace
     and routines.prorettype <> 'trigger'::regtype
     and not exists (
       select 1
       from pg_depend as dependencies
       where dependencies.classid = 'pg_proc'::regclass
         and dependencies.objid = routines.oid
         and dependencies.deptype = 'e'
     )
     and has_function_privilege(grantee, routines.oid, 'execute')
   group by grantee
   order by grantee;
   ```

   Expect `true, false, false, false, false`, then 52 for `authenticated` and
   27 for `service_role` (the grant maps in `rls_policies.test.sql`). Rerun the
   rest of step 2: `n` (set null), the three column rows, `202610150001` and
   still `2026-09-29`.
5. **Publish the Terms.** Commit and push; Cloudflare Workers Builds rebuilds
   the site. `https://ninai.app/termos/` must read "Atualizados em 15 de
   outubro de 2026", §5 must say the titular leaves by passing or deleting the
   house, and the page must keep `data-legal-launch="ready"`.
6. **Move the recorded Terms version**, only after step 5 is live:

   ```sql
   update private.age_policy
   set current_terms_version = '2026-10-15', updated_at = now()
   where singleton;

   select current_terms_version, current_policy_version, current_minor_consent_version
   from private.age_policy;
   ```

   Expect `2026-10-15`, `2026-09-29`, `2026-09-29`. The privacy policy and the
   minors' consent text did not change, so their versions stay and no AI
   consent is withdrawn.

**What testers then see.** Every adult meets "Os Termos mudaram." once, on the
next load, and taps Aceitar; every minor acknowledges the Terms again; a
welcome footnote shown before 15 October and read back after a relaunch no
longer counts, so that person sees the gate too. "Apagar a casa" itself reaches
people with the first build after 14; until then the Terms describe a deletion
only the server offers. The local stack keeps `2026-09-29`, because no
migration carries the version.

### The rating of 14, and the Terms of 18 October

On 2026-10-15 the ClassInd coordination read Nina as tending to 14 (D.5.1 and
D.5.3, no attenuator for interactive elements), and on 2026-10-18 Heitor
accepted it (`docs/privacy/classificacao-indicativa.md` §9). Nothing on the
database changes but the recorded Terms version: the rating is one constant in
the app and the website, and the chat and Premium stay as they are. Terms §4
now names the rating as 14, so by Heitor's rule of 2026-10-15 the recorded
version follows the date the page shows.

1. **Repository gate.** `NinaRating.currentCode` and `ninaRatingCode` read
   `"14"` in the same commit, and `repository.rating-constant-consistency`
   passes:

   ```sh
   npx deno task preflight:repo
   ```

2. **Publish the site.** Commit and push; Cloudflare Workers Builds rebuilds
   it. `https://ninai.app/termos/` must read "Atualizados em 18 de outubro de
   2026", and its §4 must name the rating as "não recomendada para menores de
   14 anos"; the footer mark on every page and `/familias/` §11 must say 14;
   every page keeps `data-legal-launch="ready"`; `https://ninai.app/familias/`
   must read "Atualizada em 18 de outubro de 2026", and its §11 must give the
   reason (the Premium subscription and the chat, both adults only).
3. **Pre-check, read only, in the SQL editor:**

   ```sql
   select current_terms_version, current_policy_version, current_minor_consent_version
   from private.age_policy;
   ```

   Expect `2026-10-15`, `2026-09-29`, `2026-09-29`. Anything else means
   production moved since 2026-10-15: stop and find out why.
4. **Move the recorded Terms version**, only after step 2 is live (not run as
   of 2026-10-18):

   ```sql
   update private.age_policy
   set current_terms_version = '2026-10-18', updated_at = now()
   where singleton;

   select current_terms_version, current_policy_version, current_minor_consent_version
   from private.age_policy;
   ```

   Expect `2026-10-18`, `2026-09-29`, `2026-09-29`. The privacy policy and the
   minors' consent text did not change, so their versions stay and no AI
   consent is withdrawn.
5. **Ship build 18**, the first build whose welcome and startup marks draw 14.
   Builds up to 17 draw "L" until people update; nothing is released, so only
   TestFlight testers see the old mark.
6. **App Store Connect** carries 14 for Brazil when the age questionnaire is
   answered (§6); how is UNVERIFIED.

**What testers then see.** Every adult meets "Os Termos mudaram." once, on the
next load, and taps Aceitar; every minor acknowledges the Terms again; a
welcome footnote shown before 18 October and read back after a relaunch no
longer counts. The local stack keeps `2026-09-29`, because no migration carries
the version.

### The AI budget of 19 October (`202610190001`)

Heitor's choice 5 of 2026-10-19 raises the AI budget to US$50 a month for
conversations and US$10 for insights. Migration
`202610190001_ai_budget_settings.sql` takes the caps out of the function
bodies into one row, `private.nina_ai_budget_settings`, which every
reservation reads; adds each house's share of the conversation pool,
`private.nina_ai_household_budget_months`, capped at US$5 (a tenth of the
pool, enforced by a CHECK on the settings row) and reserved, settled and
month-pinned exactly like the pool under the same `reserved + spent <= cap`
CHECK; gives this month's pool rows the new caps and fills each house's share
for this month from its runs; makes the weekly insight describe the last whole
Monday-to-Sunday week in São Paulo, in a stable order; settles every run left
open for more than fifteen minutes from the daily retention; and revokes
PUBLIC's execute on `private.current_month_start()` and
`private.invoke_nina_maintenance()`. A house past its share is refused with
`nina_budget_exceeded`, the code `nina-chat` already answers as 429
`monthly_budget_reached` and every build already shows as "Conversa pausada.
Anote pelo + em Hoje.", so the migration needs no function deploy and no
build. Run it at a quiet hour: a turn that begins on the old body and settles
on the new one is booked on the house share without its reservation, which can
only under-count that house by one turn.

1. **Local gate.** From a clean export (`git archive` of the commit, `CLAUDE.md`
   §12), `deno task db:reset && deno task db:test` (852 assertions on
   2026-10-19).
2. **Pre-check, read only, in the SQL editor.** Production must still run the
   bodies the migration replaces:

   ```sql
   select routines.oid::regprocedure, md5(routines.prosrc)
   from pg_proc as routines
   join pg_namespace as namespaces on namespaces.oid = routines.pronamespace
   where (namespaces.nspname, routines.proname) in (
     ('public', 'begin_nina_chat_run'),
     ('public', 'complete_nina_chat_run'),
     ('public', 'record_failed_nina_ai_run'),
     ('public', 'reserve_nina_insight_run'),
     ('public', 'complete_nina_insight_run'),
     ('private', 'settle_household_ai_runs'),
     ('private', 'nina_weekly_metrics'),
     ('public', 'get_nina_weekly_candidates'),
     ('public', 'run_nina_retention'),
     ('private', 'nina_insight_period_start'),
     ('private', 'settle_abandoned_ai_runs')
   )
   order by 1;

   select
     to_regclass('private.nina_ai_budget_settings'),
     to_regclass('private.nina_ai_household_budget_months');

   select month_start, purpose, cap_microusd, reserved_microusd, spent_microusd
   from public.nina_ai_budget_months
   where month_start = date_trunc('month', now())::date
   order by purpose;

   select max(version) from supabase_migrations.schema_migrations;
   ```

   Expect exactly nine functions: `begin_nina_chat_run(…)`
   `aeebbfa060c94d07d637815b1acd318b`, `complete_nina_chat_run(…)`
   `5382e2fd7916df4136d2276373bebfc2`, `complete_nina_insight_run(…)`
   `5151924bfabe8868a18272ffcabf7068`, `get_nina_weekly_candidates()`
   `e95ded4bb34d6f8bbda5ea9d157666d3`, `private.nina_weekly_metrics(uuid)`
   `dd1f9f647ecd68b838f166a2fdd4b153`, `private.settle_household_ai_runs(uuid)`
   `b40485125ad32a93f118120bab887d2b`, `record_failed_nina_ai_run(…)`
   `43c3bc9bf6760a9648e90278119c80f7`, `reserve_nina_insight_run(…)`
   `2fe59a3bb7102b392a770f7b3ed72809` and `run_nina_retention()`
   `45b9504c349019282403b680102cb5e4`; then two nulls; this month's pool rows
   at caps `20000000` (interactive) and `5000000` (insights), or no row for a
   purpose nothing spent on this month (write down their reserved and spent);
   and `202610150001`, or the migration of 19 October applied just before this
   one. Any other body means production drifted from the repository: stop and
   compare before applying.
3. **Apply the migration**, either with `npx supabase db push` from the clean
   export (the dry run must list only `202610190001_ai_budget_settings`) or
   through the Supabase MCP `apply_migration` named `ai_budget_settings` with
   the file's body. The MCP records a 14-digit version, so repair it at once:

   ```sql
   update supabase_migrations.schema_migrations
   set version = '202610190001'
   where name = 'ai_budget_settings'
     and version <> '202610190001';
   ```

4. **Read back.** Rerun the first query of step 2. Expect eleven functions:
   `begin_nina_chat_run(…)` `84b84c82a056703be563206915c34102`,
   `complete_nina_chat_run(…)` `7fda278312aaf8f225378fd0951b33c2`,
   `complete_nina_insight_run(…)` `f010e6696f4c653ba300420fb7b1759b`,
   `get_nina_weekly_candidates()` `469f5b55bd4dc78d4975532ae63dc98e`,
   `private.nina_insight_period_start(timestamp with time zone)`
   `096a4809f0ba658faf9420f09cd0e8e8`, `private.nina_weekly_metrics(uuid)`
   `fe2011c8a4e397c9f6e5a074bd800d16`, `private.settle_abandoned_ai_runs()`
   `fb1f919447eae54b1cbd51dc0c9b912c`, `private.settle_household_ai_runs(uuid)`
   `5b145882bc1488103c76952052731720`, `record_failed_nina_ai_run(…)`
   `ef6a27ebee06a432996415ce4f02b7fc`, `reserve_nina_insight_run(…)`
   `463e2b230fd367aeec2650b9dde00281` and `run_nina_retention()`
   `a8b3e5e8649eb1df1fd997c029f3fd2b`. Then:

   ```sql
   select singleton, interactive_cap_microusd, insights_cap_microusd,
          household_interactive_cap_microusd
   from private.nina_ai_budget_settings;

   select month_start, purpose, cap_microusd, reserved_microusd, spent_microusd
   from public.nina_ai_budget_months
   where month_start = date_trunc('month', now())::date
   order by purpose;

   select count(*), sum(reserved_microusd), sum(spent_microusd),
          max(reserved_microusd + spent_microusd)
   from private.nina_ai_household_budget_months
   where month_start = date_trunc('month', now())::date;

   select
     has_function_privilege('public', 'private.current_month_start()', 'execute'),
     has_function_privilege('public', 'private.invoke_nina_maintenance()', 'execute'),
     has_function_privilege('service_role', 'private.settle_abandoned_ai_runs()', 'execute'),
     has_table_privilege('service_role', 'private.nina_ai_budget_settings', 'select'),
     has_table_privilege('service_role', 'private.nina_ai_household_budget_months', 'select');

   select jobname, schedule, command, active
   from cron.job
   where jobname = 'nina-daily-maintenance';

   select private.nina_insight_period_start(now()),
          private.nina_insight_period_start(now()) + 6;

   select max(version) from supabase_migrations.schema_migrations;
   ```

   Expect `true, 50000000, 10000000, 5000000`; this month's pool rows at
   `50000000` and `10000000` with the reserved and spent written down in step
   2; one share row per house that talked to Nina this month, its reserved and
   spent equal to that house's runs (the pool's spent also holds what deleted
   houses spent, so the sums may be lower), and a largest total of at most
   `5000000` (a house above it is already over its share and pauses until
   November); five `false`; the job at `15 6 * * *` running
   `select private.invoke_nina_maintenance()`, active (pg_cron runs it as its
   owner, whom the revoke leaves alone); the last whole Monday-to-Sunday week;
   and `202610190001`. Rerun the grant count of the house deletion's step 4:
   still 52 for `authenticated` and 27 for `service_role`. Then the
   foreign-key canary of `foreign_key_indexes.test.sql`, which must read 0:

   ```sql
   select count(*)
   from pg_constraint as constraints
   join pg_namespace as namespaces on namespaces.oid = constraints.connamespace
   where constraints.contype = 'f'
     and namespaces.nspname in ('public', 'private')
     and not exists (
       select 1
       from pg_index as indexes
       where indexes.indrelid = constraints.conrelid
         and (indexes.indkey::int2[])[0:array_length(constraints.conkey, 1) - 1]
           = constraints.conkey
     );
   ```
5. **The next morning**, the maintenance answer carries
   `retention.abandoned_runs` (the runs it settled), and an insight is written
   at most once per house per week.

**Raising a cap later** is one statement; the next reservation copies the row
onto this month's pool row and house share, so it takes effect the same month:

```sql
update private.nina_ai_budget_settings
set interactive_cap_microusd = 80000000,
    household_interactive_cap_microusd = 8000000
where singleton;
```

The house share can never be more than a tenth of the pool, so raising the
share alone past that is refused (`23514`); move both in the one statement.
`insights_cap_microusd` moves the same way. A lowered cap holds what was
already spent and reserves nothing more past it that month. Keep the OpenAI
project budget above the new sum (§2, "OpenAI dashboard").

**What testers then see.** Nothing, until a house spends US$5 of
conversations in a month: from then on that house reads "Conversa pausada.
Anote pelo + em Hoje." until the month turns, while every other house keeps
talking. The weekly summary covers the last whole Monday-to-Sunday week and
comes at most once a week; before, a covered house with five events in the
last seven days was chosen again every night.

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
badge and offers the waitlist instead, and the landing says "Ainda em teste,
fora da App Store.". **Set it in the Cloudflare build variables only once the
app is live on the App Store** (§8, launch day), never when the record merely
exists in App Store Connect: the record has existed since 2026-09-03, but
until Release is pressed and Apple's lookup finds the app, the store page does
not exist, and a badge built earlier links to nothing (`CLAUDE.md` §13). The
inventory in `config/production.env` already carries the same number, because
the preflight's `environment.app-store-id-parity` compares it with
`NINA_APP_APPLE_ID`; only the Cloudflare build variable decides what the site
shows. After setting it, rebuild through Cloudflare Workers Builds from git: a
Cloudflare variable change alone leaves the install path hidden, and a local
`wrangler deploy` builds without the legal values.

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

### What the next build carries

Build 20 is the release candidate. If another build is cut before submission,
it also carries these, found on 2026-10-20 and not worth a build alone:

- The account deletion sheet says what stays by law: the access records for
  the rest of their six months (Marco Civil art. 15) and the guardianship and
  consent proof for five years. Apple's account-deletion guidance asks for it;
  the privacy policy already says it.
- `Nina/PrivacyInfo.xcprivacy` lists the data types Nina collects
  (`NSPrivacyCollectedDataTypes`), matching `docs/privacy/app-store-privacy-labels.md`.

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
- no screen shows the rating mark (removed in build 19, 2026-10-19; builds
  11 to 18 showed it on the welcome and the startup screen); the "Só um
  instante." wait is centred with a round disc.

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
   since 2026-10-18 the rating Nina publishes is already 14 (how the App Store
   listing reads 14 is UNVERIFIED, item 2), so only a reading above 14 moves
   it. The App Review page cannot start a
   conversation without a submission (checked 2026-09-29), and the "Contact us"
   form is for rejections. A free 30-minute App Review appointment (Meet with
   Apple, Tuesdays and Thursdays:
   `https://developer.apple.com/events/view/upcoming-events?search=Review`)
   gets the answers before submitting, if that ever matters more than the call.
   The four questions, reworded on 2026-10-19 for the rating of 14 and for D3,
   are in the one final review note, `docs/app-store-listing.md` §6, and in
   the rating document's §3, word for word in both; this runbook no longer
   carries a third copy.

   Record the answers in the rating document. The first submission carries the
   honest answers, with the Brazil listing raised to 14, and these questions
   beside them in the notes, so the reviewer sees both at once; the notes also
   carry the age-rating sentence. All four questions stay after the 2026-10-18
   decision (the rating document's §3 says why). If the answers push the rating above 14, the product question goes
   back to Heitor first; any change moves `NinaRating.currentCode`,
   `web/src/rating.ts` and the Terms together, and
   `repository.rating-constant-consistency` fails until they agree.

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
   Override to a higher rating: whatever makes the Brazil listing read 14,
   ClassInd's reading (how App Store Connect maps an override onto Brazil is
   UNVERIFIED; read it there and record it in the rating document's §9). Never
   for a minimum age: the Terms set none.
3. **Metadata:** no "para crianças" in the name, subtitle, icon, screenshots or
   description, and screenshots that suit every age. The listing is "Nina:
   rotina da casa" since 2026-10-05; the old name said "amiga".
4. **ClassInd (MJSP):** the coordination answered on 2026-10-15 that Nina
   tends to 14 (D.5.1 and D.5.3, no attenuator for interactive elements), and
   Heitor accepted 14 on 2026-10-18. Next, file the voluntary análise prévia
   (Portaria art. 46) through the Sistema ClassInd, the route ClassInd named
   (the App Store is not part of IARC); not filed yet. The filing needs a
   video demonstrating every feature open to classification, plus an access
   link, login and password when full access needs them; Sign in with Apple
   is the only sign-in, so how the analyst reaches the adult features is open.
   Whether an Inova Simples company files through its titular was not
   answered, and the cost is UNVERIFIED. If the Ministry rates Nina lower,
   the constant goes back down (the rating document's §8). The company's name
   and CNPJ go into the filing, never into this repository.
5. **Before release, read from the official source and correct if needed:** the
   ClassInd pictogram artwork and colours (gov.br/mj; `Nina/Theme.swift` and
   `web/src/rating.ts`), the Polícia Federal intake for child-safety reports
   (the MJSP act is Portaria MJSP 1.312/2026, but its NIDUS system takes no
   reports yet and the interim channel is undecided:
   `docs/child-safety-runbook.md` §5), and Apple's App Attestation Root CA
   (compare with the embedded copy in `_shared/app-attest.ts`). Read on
   2026-10-19 and right, so nothing changes: the CVV number 188 (cvv.org.br;
   `MinorViews.swift`, `/familias/`, the prompt), the 190 and Disque 100
   numbers on `/denuncia/` (the federal government's Secom guide), and the
   OpenAI sub-processor link in `privacidade.astro`,
   `https://platform.openai.com/subprocessors`. OpenAI's Data Processing
   Addendum v.010126 defines its "Sub-Processor List" as "the list available
   at the following address https://platform.openai.com/subprocessors"
   (cdn.openai.com/pdf/openai-data-processing-addendum.pdf), and in a browser
   that address redirects to `https://openai.com/policies/sub-processor-list/`
   (curl gets a Cloudflare challenge). The DPA's own address stays.

### App Store Connect settings

Set once for version 1.0 and read again before every submission. The words
(name, subtitle, description, keywords, subscription names, review notes) are
in `docs/app-store-listing.md`; this is everything else. App Store Connect
renames its pages; where a label differs, record what it is called now.

- [ ] **Availability: Brazil only.** Pricing and Availability › Countries or
  Regions lists Brazil and nothing else. The app is in Brazilian Portuguese,
  its servers and its law are Brazil's, and both subscriptions are priced in
  reais.
- [ ] **iPhone only.** Untick availability on Apple Silicon Macs and on Apple
  Vision Pro (both are on by default for an iPhone app). Nina is
  `TARGETED_DEVICE_FAMILY = 1`, was never tested on either, and leans on App
  Attest and Declared Age Range, which behave differently there.
- [ ] **Age Rating.** Answer as `docs/privacy/classificacao-indicativa.md` §2
  says, so the Brazil listing reads 14, and record there (§9) what App Store
  Connect offered for it. Made for Kids: No. Age Suitability URL:
  `https://ninai.app/familias/`.
- [ ] **App Privacy.** The answers in `docs/privacy/app-store-privacy-labels.md`,
  Purchase History, Health and Photos or Videos included.
- [ ] **Every URL with its trailing slash** (the slashless form answers a 307
  first): Support `https://ninai.app/suporte/`, Marketing
  `https://ninai.app/`, Privacy Policy `https://ninai.app/privacidade/`, Age
  Suitability `https://ninai.app/familias/`, and the Terms link in the
  description `https://ninai.app/termos/`.
- [ ] **Categories:** primary Productivity (Produtividade), secondary Lifestyle
  (Estilo de vida).
- [ ] **App Review Information.** "Sign-in required" off: Sign in with Apple is
  the only door and there is no user name or password to give. Contact name,
  phone and email are typed there and never into this repository. Notes: the
  text in `docs/app-store-listing.md` §6, as it stands.
- [ ] **Export compliance.** `ITSAppUsesNonExemptEncryption` is `false` in
  `Nina/Info.plist`, so no build asks.
- [ ] **The subscription group "Nina Premium"** (Monetization ›
  Subscriptions), as in `Nina/Nina.storekit`:
  - group display name "Nina Premium", in Portuguese (Brazil);
  - `com.heitor.nina.premium.monthly`: reference name "Nina Premium mensal",
    duration 1 month, Brazil price R$ 24,90, available in Brazil only;
  - `com.heitor.nina.premium.yearly`: reference name "Nina Premium anual",
    duration 1 year, Brazil price R$ 249,90, available in Brazil only;
  - both on the same level of the group (the same Premium, two durations), no
    introductory or promotional offer;
  - each with the display name and description of `docs/app-store-listing.md`
    §5 in Portuguese (Brazil), its own review screenshot of the paywall and a
    one-line review note;
  - Family Sharing on, as it has been since 2026-09-03 (Apple never lets it be
    turned off); the description says it does not unlock Premium;
  - App Store Server Notifications, version 2, for Production and Sandbox:
    `https://apemftmlsjocvifbptum.supabase.co/functions/v1/app-store-server-notifications`
    (set and confirmed 2026-09-09);
  - both added to the version under "In-App Purchases and Subscriptions", so
    they go to review with the app's first version.
- [ ] **Version Release: "Manually release this version"** (Heitor's choice 4
  of 2026-10-19). An approved version then waits in "Pending Developer
  Release" until §8.
- [ ] **TestFlight.** The public link carries a tester limit (§2), and is
  turned off on launch day (§8).

### The reviewer's account

The reviewer signs in with their own Apple Account, so nothing can be prepared
before the review. A reviewer whose device shares an 18+ range needs nothing
from the operator. One whose device shares no age reads as unknown, sees a
minor's screens, and is asked in the review notes to reply with the time they
signed in. Mark only that account, and only with `trusted = false` (Heitor's
choice 3 of 2026-10-19): `private.operator_set_age_status` then records a
self-declared adult, which chats and buys Premium under D3's policy row but is
never trusted for a minor (`private.is_trusted_adult` takes `confirmed` or
`operator` only). `true` would record `operator`, which approves, adds and
answers for children; never use it for the reviewer.

1. **Find the account** from the time the reviewer gives (an account made since
   build 11 carries no email):

   ```sql
   select users.id, users.created_at, users.last_sign_in_at,
          ages.status, ages.band_source, ages.assurance,
          ages.minor_since, ages.household_marked, ages.has_record
   from auth.users as users
   cross join lateral private.effective_age(users.id) as ages
   where users.created_at between timestamptz '<UTC time>' - interval '15 minutes'
                              and timestamptz '<UTC time>' + interval '15 minutes'
   order by users.created_at;
   ```

   Expect one row whose status is `unknown`. More than one, or none: ask the
   reviewer for a closer time in the submission's messages; never mark a
   guess. **If the row's status is `minor`, or `minor_since` is not null, or
   `household_marked` is true, mark nothing** and answer the reviewer that
   this account cannot be used: it holds a minor record (Apple's band, a
   guardian's approval or a child's profile in a house), and marking it adult
   would end that minor's guardianships and consents.
2. **Mark it**, with step 1's check repeated in the statement:

   ```sql
   select private.operator_set_age_status(users.id, 'adult', null, false, 'app_review')
   from auth.users as users
   cross join lateral private.effective_age(users.id) as ages
   where users.id = '<reviewer auth user id>'
     and ages.status = 'unknown'
     and ages.minor_since is null
     and not ages.household_marked;
   ```

   It must return one row. The operator path enforces no ratchet
   (`private.operator_set_age_status` calls `private.store_age_status` with
   `enforce_ratchet` false, so `age_signal_rejected` never comes back from
   it): a minor's account marked adult is released as if it had reached
   majority. Step 1's check, repeated in this `where`, is the only guard; no
   row returned means nothing was marked, so go back to step 1.
3. **Read it back:**

   ```sql
   select private.may_use_ai('<reviewer auth user id>') as may_use_ai,
          public.premium_buyer_is_eligible('<reviewer auth user id>') as may_buy,
          private.is_trusted_adult('<reviewer auth user id>') as acts_for_minors;
   ```

   Expect `true`, `true`, `false`, then answer in the submission's messages
   that the account is ready. The reviewer refreshes the house (pull to
   refresh, or leave and return to the app). This mark is a self-declared
   record, so unlike an `operator` mark (`202610140001`) it does not outlive
   the reviewer's phone: a later declined or minor signal from that device
   replaces it. If the reviewer writes that the chat closed again, read the
   row and mark it again.
4. **Unmark it** on launch day (§8), or when a review ends without a release:

   ```sql
   select private.operator_set_age_status('<reviewer auth user id>', 'unknown', null, false, 'app_review_ended');

   select status, assurance from private.account_age_status
   where user_id = '<reviewer auth user id>';
   ```

   Expect `unknown` and `none`. The ratchet applies at once: the account's AI
   consent is withdrawn and it can no longer chat or buy; a house it created
   keeps its rows, and its titular keeps the role without the powers. A later
   review (an update) starts again at step 1.

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
  maintenance, subscription notifications, AI budget, and crash diagnostics,
  and that person has read `docs/incident-runbook.md` and run the restore drill
  (§9) once.

## 8. Launch day

**Release waits for the Ministry: press Release only after the análise
prévia's result or a written yes from ClassInd** (Heitor's choice 4 of
2026-10-19; `docs/privacy/classificacao-indicativa.md` §9). The version went to
App Review with "Manually release this version" (§6), so an approved version
waits in "Pending Developer Release" for as long as that takes. Record the
result or the yes in the rating document's §9 first; then, in order:

1. **Press Release** on the version in App Store Connect.
2. **Wait until Apple's lookup finds the app.** The store page and the badge
   link work only from then on, and the delay after Release is UNVERIFIED
   (often hours):

   ```sh
   curl -s 'https://itunes.apple.com/lookup?id=6808423946&country=br' | grep -o '"resultCount":[0-9]*'
   ```

   It must print `"resultCount":1`. While it prints `0`, stop here.
3. **Set `PUBLIC_NINA_APP_STORE_ID=6808423946`** in the Cloudflare build
   variables of the site's Worker (Workers Builds, beside the legal values;
   build variables, not runtime ones). `config/production.env` already holds
   the same number (§4).
4. **Rebuild only through Cloudflare, from git**: retry the latest Workers
   Builds build in the dashboard, or push a commit to `main`. Never
   `wrangler deploy` from the Mac: a local build has none of the legal build
   variables and publishes `data-legal-status="incomplete"` (`CLAUDE.md` §13).
5. **Check the live site**:

   ```sh
   curl -s https://ninai.app/ | grep -c 'apps.apple.com/br/app/id6808423946'
   curl -s https://ninai.app/ | grep -c -E 'quase pronta|Ainda em teste|data-waitlist-dialog'
   curl -s https://ninai.app/ | grep -c 'name="apple-itunes-app"'
   curl -s https://ninai.app/join/ | grep -c 'apps.apple.com/br/app/id6808423946'
   curl -s https://ninai.app/termos/ | grep -o 'data-legal-launch="[a-z]*"'
   ```

   Expect at least 1, then 0, 1, at least 1, and `data-legal-launch="ready"`.
   Then, on an iPhone, tap the landing's badge and an invite link's badge: both
   open Nina's page in the App Store. Run the online gate:

   ```sh
   npx deno task preflight:production --env-file config/production.env --online
   ```

6. **Turn off the public TestFlight link** (App Store Connect › TestFlight ›
   the external group › Public Link). Every sandbox purchase covers a house for
   free (§2), and nobody needs the link once the app is in the store.
7. **Remove the reviewer's mark** (§6, "The reviewer's account", step 4).
8. **Read the service every day for the first 48 hours** (on day 1 and day 2,
   morning and evening):
   - the daily maintenance ran: one `2xx` from `nina-maintenance` after 06:15
     UTC in its function logs, no `minor_account_deletion_failed` or retention
     error, and

     ```sql
     select status, start_time, return_message
     from cron.job_run_details
     where jobid = (select jobid from cron.job where jobname = 'nina-daily-maintenance')
     order by start_time desc
     limit 3;
     ```

   - every function's logs for non-2xx answers and their stable codes
     (`monthly_budget_reached`, `age_signal_failed`,
     `apple_token_revocation_failed`, `service_not_configured`);
   - the AI budget (the query in §2, "OpenAI dashboard") against OpenAI's
     Usage page;
   - how real iPhones come back, and how many people arrived:

     ```sql
     select * from private.age_assurance_distribution();

     select count(*) as accounts,
            count(*) filter (where created_at > now() - interval '1 day') as new_today
     from auth.users;

     select count(*) as houses from public.families;

     select environment, status, count(*)
     from public.premium_subscriptions
     group by 1, 2
     order by 1, 2;
     ```

   - the child-safety reads (`docs/child-safety-runbook.md` §6) and the
     privacy and report mailbox (48-hour acknowledgement);
   - `curl -s -o /dev/null -w '%{http_code}\n' https://ninai.app/api/health`
     prints `200`;
   - App Store Connect's ratings and reviews, and crashes in Xcode's
     Organizer.

   Anything that reads wrong goes to `docs/incident-runbook.md`. The one
   waitlist email (§4) may go once the badge is live; when is Heitor's call.

## 9. Restore

**What a backup holds.** Supabase keeps daily backups on the Pro plan and
above, seven days of them on Pro; a project on the Free plan has none, so
production must be on Pro before launch. A backup is the Postgres database
only: every schema, `auth` (the accounts), `private` (ages, guardianships,
holds) and `cron` included. It does not hold the files in Storage (profile
photos: the `storage.objects` rows come back, files deleted since do not), the
Edge Functions or their secrets, the Auth provider settings, or the API keys.
Restoring in place replaces the whole database with the backup, takes the
project offline while it runs, and loses everything written after the backup's
time. How long it takes for Nina's size is UNVERIFIED until the first drill.

Restore only when the data itself is lost or corrupted and nothing narrower
repairs it. A broken migration or function is fixed forward (§3), never by a
restore.

### Restoring production from a daily backup

1. **Pick the backup.** Dashboard › Database › Backups lists the daily backups
   with their times (UTC). Choose the newest one from before the damage and
   write its time down.
2. **Save what the restore would undo.** The restore puts every row back as it
   stood at the backup's time, so whatever people did since that protected
   someone (a removal, a departure, a withdrawal, a deletion, a hold closed) is
   undone with the rest, and only these values let step 4 do it again. Run each
   statement on production and save each value as printed (one `{…}` array or
   JSON object per statement, rows for the ages and the last query: ids,
   roles, reasons, bands and times only) under its column's name, into a
   private folder outside this repository and
   outside iCloud (`~/nina-restore/`, mode 700), deleted at step 6:

   ```sql
   select coalesce(array_agg(id order by id), '{}') as accounts from auth.users;
   select coalesce(array_agg(id order by id), '{}') as houses from public.families;
   select coalesce(array_agg(id order by id), '{}') as members from public.family_members;
   select coalesce(jsonb_object_agg(id, permission_role), '{}') as owners_and_admins
   from public.family_members where permission_role in ('owner', 'admin');
   select coalesce(array_agg(id order by id), '{}') as withdrawn_ai_consents
   from public.nina_ai_consents where revoked_at is not null;
   select coalesce(array_agg(id order by id), '{}') as withdrawn_minor_consents
   from private.minor_data_consents where withdrawn_at is not null;
   select coalesce(jsonb_object_agg(id, end_reason), '{}') as ended_guardianships
   from private.minor_guardianships where ended_at is not null;
   select coalesce(array_agg(id order by id), '{}') as health_tasks
   from public.tasks where category_id = 'health';
   select user_id, status, minor_band from private.account_age_status
   where status <> 'adult' order by user_id;
   select coalesce(jsonb_object_agg(id, jsonb_build_object(
            'reported_at', reported_at,
            'authority_receipt_at', authority_receipt_at,
            'deleted_at', deleted_at)), '{}') as closed_holds
   from private.child_safety_holds
   where reported_at is not null or authority_receipt_at is not null or deleted_at is not null;
   select coalesce(array_agg(hold_id order by hold_id), '{}') as preserved_accounts
   from private.child_safety_preserved_accounts;
   select coalesce(jsonb_object_agg(user_id, reason_code), '{}') as active_blocks
   from private.nina_ai_blocks where lifted_at is null;
   select coalesce(array_agg(id order by id), '{}') as memories from public.memory_items;
   select coalesce(array_agg(id order by id), '{}') as private_memories
   from public.memory_items where visibility = 'private';
   select coalesce(array_agg(id order by id), '{}') as proposals from public.nina_proposals;
   select coalesce(jsonb_object_agg(thread_id, oldest), '{}') as oldest_message_per_thread
   from (
     select thread_id, min(created_at) as oldest
     from public.chat_messages
     where thread_id is not null
     group by thread_id
   ) as threads;
   select id, created_at from private.child_safety_holds
   where deleted_at is null and created_at > timestamptz '<backup time>';
   ```

   A hold the last query lists exists only in the live database, and the
   restore erases it: finish `docs/child-safety-runbook.md` §2 for it (decide,
   and report it if it is to be reported) before going on; its block survives
   through `active_blocks`.

   **If production does not answer**, nothing can be saved, and step 4 cannot
   undo what people did since the backup. Stop: it is an incident
   (`docs/incident-runbook.md` §1). Heitor decides with the encarregado whether
   to restore anyway, and the Data API stays off (step 3) until what came back
   has been found and undone some other way.
3. **Restore, and keep the service closed.** On the chosen backup, Restore,
   confirm, and wait until the project answers again. Then turn the Data API
   off at once (Project Settings › Data API, "Enable Data API"; the drill
   proves the switch): until step 4 is done, the restored database lets a
   removed member read the house again and a deleted account answer to its
   Apple ID, so no phone may reach it. Auth, Storage and the SQL editor keep
   working, which is all step 4 needs; every app request and every Edge
   Function fails until step 5.
4. **Undo what the backup brought back**, in this order, in the SQL editor,
   pasting each saved value of step 2 whole where its name appears in angle
   brackets. **If a saved value is missing, or any statement fails or reads
   otherwise than this step says, stop with the Data API still off**: it is an
   incident (`docs/incident-runbook.md` §1), and Heitor decides with the
   encarregado before anything reopens.
   - **Child-safety holds closed after the backup are open again**, their
     content back in the database, which the law allows holding only to report
     it (ECA art. 241-B §2 III); an account copy retention had dropped is back,
     and so is a block that was lifted. Close, drop and lift them again, and
     block again what was blocked since:

     ```sql
     update private.child_safety_holds as holds
     set reported_at = (saved.value ->> 'reported_at')::timestamptz,
         authority_receipt_at = (saved.value ->> 'authority_receipt_at')::timestamptz,
         deleted_at = (saved.value ->> 'deleted_at')::timestamptz,
         content = case when saved.value ->> 'deleted_at' is null then holds.content else '' end
     from jsonb_each('<closed_holds>'::jsonb) as saved
     where holds.id = saved.key::uuid;

     delete from private.child_safety_preserved_accounts
     where hold_id <> all ('<preserved_accounts>'::uuid[]);

     select private.operator_lift_ai_block(blocks.user_id, 'restore_replay')
     from private.nina_ai_blocks as blocks
     where blocks.lifted_at is null
       and not ('<active_blocks>'::jsonb ? blocks.user_id::text);

     insert into private.nina_ai_blocks (user_id, reason_code)
     select saved.key::uuid, saved.value
     from jsonb_each_text('<active_blocks>'::jsonb) as saved
     where exists (select 1 from auth.users where users.id = saved.key::uuid)
     on conflict (user_id) do update
     set reason_code = excluded.reason_code, created_at = now(),
         lifted_at = null, lift_reason_code = null
     where nina_ai_blocks.lifted_at is not null;
     ```

   - **Accounts deleted after the backup are back.** List them:

     ```sql
     select id, created_at from auth.users
     where id <> all ('<accounts>'::uuid[]);
     ```

     Delete each again exactly as §2, "Deletion requests by mail", step 5 does
     (Storage `profile-photos/<uid>/` first, then the Auth user; the trigger
     runs `prepare_account_deletion`). A person who deleted their account was
     told it was gone, so this is not optional (LGPD art. 18 VI). Accounts
     created after the backup are lost instead; their owners sign in again and
     get a new account.
   - **Houses deleted after the backup are back.** The same comparison on
     `public.families` with `<houses>`, after the accounts above are deleted
     (an account deletion that left no adult deletes its house too). For each
     house still listed, read its titular and delete it the way `delete_family`
     does:

     ```sql
     select user_id from public.family_members
     where family_id = '<family id>' and permission_role = 'owner';

     select private.delete_household('<family id>', '<titular auth user id>');
     ```

   - **Titulars and admins read as they did at the backup**: a house handed
     over since is its former titular's again, and an admin demoted since has
     the powers back. List every row whose role differs from the saved one (a
     row production no longer has counts as `member`; the next item removes
     it):

     ```sql
     select members.id, members.family_id, members.user_id, members.permission_role,
            coalesce('<owners_and_admins>'::jsonb ->> members.id::text, 'member') as saved_role
     from public.family_members as members
     where members.household_role <> 'assistant'
       and members.permission_role
         <> coalesce('<owners_and_admins>'::jsonb ->> members.id::text, 'member')
     order by members.family_id;
     ```

     For each house listed, set each row to its saved role, the demotions
     first and the titular last, then move the house's `created_by` to the
     titular's user id, as `accept_family_ownership_offer` does:

     ```sql
     update public.family_members set permission_role = '<saved_role>'
     where id = '<member id>';

     update public.families set created_by = '<titular auth user id>', updated_at = now()
     where id = '<family id>';
     ```

     A row that refuses `admin` or `owner` belongs to someone whose majority
     came after the backup and whose restored age reads minor again: leave it
     `member`, and if that leaves the house without a titular, stop.
   - **People removed from a house, or gone from it, after the backup are back
     in it**, and membership is the authorization boundary (`CLAUDE.md` §4).
     List them:

     ```sql
     select id, family_id, user_id, household_role, permission_role
     from public.family_members
     where id <> all ('<members>'::uuid[]);
     ```

     After the accounts, houses and roles above, every row listed came back
     after its person was removed or left. An `assistant` row, or one still
     `owner`, cannot have: stop. Otherwise remove them again, and take the
     house off their profiles, where a Premium bound to it would go on
     covering it:

     ```sql
     delete from public.family_members
     where id <> all ('<members>'::uuid[])
       and household_role <> 'assistant'
       and permission_role <> 'owner';

     update public.profiles as profiles
     set active_family_id = null
     where profiles.active_family_id is not null
       and not exists (
         select 1 from public.family_members as members
         where members.user_id = profiles.id
           and members.family_id = profiles.active_family_id
       );
     ```

     The `BEFORE DELETE` trigger on `family_members` closes a removed child's
     or teen's links and consents again; what a removed adult held comes next.
     Their removal notice is lost with the rest, and people who joined after
     the backup are lost too and ask to join again.
   - **Guardianships ended and minor consents withdrawn after the backup are
     live again**: an adult who left the ward's house would act for the child
     again, and a withdrawn health consent would allow health reminders. End
     and withdraw them again, and delete again every health reminder deleted
     since, the ones a withdrawal deleted (`set_minor_health_consent`)
     included:

     ```sql
     update private.minor_guardianships as links
     set ended_at = now(), end_reason = saved.value
     from jsonb_each_text('<ended_guardianships>'::jsonb) as saved
     where links.id = saved.key::uuid
       and links.ended_at is null;

     update private.minor_data_consents
     set withdrawn_at = now()
     where id = any ('<withdrawn_minor_consents>'::uuid[])
       and withdrawn_at is null;

     delete from public.tasks
     where category_id = 'health'
       and id <> all ('<health_tasks>'::uuid[]);
     ```

     A replayed row carries the replay's time, not the original one.
   - **AI consents withdrawn after the backup read live again**, so the chat
     would send that adult's words to OpenAI without consent. Withdraw them
     again:

     ```sql
     update public.nina_ai_consents
     set revoked_at = now(), revoke_reason = 'withdrawn'
     where id = any ('<withdrawn_ai_consents>'::uuid[])
       and revoked_at is null;
     ```

   - **Ages that moved toward protection after the backup read as before.**
     For each saved row whose restored status now reads `adult`, set it back
     with `private.operator_set_age_status('<user id>', '<saved status>',
     '<saved band or null>', false, 'restore_replay')` and read the row back.
   - **Memories, proposals and conversations erased after the backup are
     back**, and would reach the model again; a memory made private since reads
     shared again. Erase them again and make that memory private:

     ```sql
     delete from public.memory_items
     where id <> all ('<memories>'::uuid[]);

     update public.memory_items
     set visibility = 'private', updated_at = now()
     where id = any ('<private_memories>'::uuid[])
       and visibility <> 'private';

     delete from public.nina_proposals
     where id <> all ('<proposals>'::uuid[]);

     delete from public.chat_messages as messages
     where messages.thread_id is not null
       and messages.created_at < coalesce(
         ('<oldest_message_per_thread>'::jsonb ->> messages.thread_id::text)::timestamptz,
         'infinity'
       );
     ```

     A conversation is erased whole (`delete_current_nina_chat_history`) and
     retention takes the oldest messages first, so each thread keeps only what
     is at least as new as its oldest message in production; the next
     retention run takes anything older this leaves.
   - **Subscriptions recorded after the backup are gone.** The subscriber's
     phone may not send its transaction again on its own (it remembers having
     sent it); "Restaurar compras" on the Premium sheet sends it, and so does
     Apple's next notification for that subscription.
   - **The month's AI budget undercounts** what OpenAI billed since the
     backup, in the pool (`public.nina_ai_budget_months`) and in each house's
     share (`private.nina_ai_household_budget_months`). Compare the pool with
     OpenAI's Usage page (§2) and tell Heitor before raising anything.
   - **Everything else reads as it stood at the backup**: tasks, lists, edits,
     invites, join requests and their answers. The house does it again in the
     app.
5. **Check, then reopen.** The newest row of
   `supabase_migrations.schema_migrations` must equal the newest migration
   applied before the backup's time; a migration applied after it is applied
   again (§3) while the Data API is still off. Then turn the Data API back on,
   and run the online gate (§4), one chat turn on a test account, and the next
   morning's maintenance run (§8, step 8).
6. **Close.** Delete `~/nina-restore/` and empty the Trash. Record the date,
   the backup's time and what step 4 replayed in the private records, never
   here. A restore that lost people's data is a security incident of
   availability: `docs/incident-runbook.md` decides whether the ANPD and the
   people are told.

### Restore drill

Once before launch and then every three months, prove that a backup restores
and how long it takes, without touching production.

1. **Only with nothing sealed in the database.** A copy of a sealed
   child-safety hold is possession of what the law allows holding only to
   report it (ECA art. 241-B §2 III). Postpone the drill while either count is
   above 0:

   ```sql
   select (select count(*) from private.child_safety_holds where deleted_at is null) as holds,
          (select count(*) from private.child_safety_preserved_accounts) as preserved;
   ```

2. **Restore the newest daily backup into a new project**, never over
   production: Dashboard › Database › Backups, "Restore to a new project", in
   the same organization and in `sa-east-1`. If the plan does not offer it for
   daily backups (UNVERIFIED), create an empty project `nina-restore-drill` in
   `sa-east-1`, download the newest daily backup from the same page into
   `~/nina-restore/` (mode 700, outside iCloud and this repository), and load
   it with `psql --dbname '<drill connection string>' --file <backup file>`
   (unzip it first if it ends in `.gz`; the file's exact form is UNVERIFIED).
   Note the minutes from start to a project that answers.
3. **Cut the copy off from production at once.** The copy carries
   production's maintenance URL and secret, and its pg_cron would call
   production's `nina-maintenance` at 06:15 UTC, a second run with a second
   bill for the insights:

   ```sql
   select cron.unschedule('nina-daily-maintenance');
   delete from private.nina_maintenance_config;
   ```

   The copy has no Edge Functions and no Auth providers configured, so nobody
   signs in to it and nothing else calls out.
4. **Read it, counts only:**

   ```sql
   select max(version) from supabase_migrations.schema_migrations;
   select count(*) from auth.users;
   select count(*) from public.families;
   select count(*) from public.tasks;
   select count(*) from private.account_age_status;
   ```

   The version must equal production's at the backup's time, and the counts
   must be close to production's (it has moved on since).
5. **Prove the restore's own steps on the copy.** Run every statement of the
   restore's step 2 there (the values stay in the SQL editor, never saved):
   each must answer, and each value must copy whole out of the result. Then
   turn the copy's Data API off (Project Settings › Data API), check that
   `curl -s -o /dev/null -w '%{http_code}\n' 'https://<drill project ref>.supabase.co/rest/v1/' -H 'apikey: <drill publishable key>'`
   prints another code than with it on while the SQL editor still answers,
   and turn it on again. A switch that is not there, or a statement that
   fails, is fixed in the restore steps before the drill is recorded.
6. **Delete the drill project** (Settings › General › Delete project) and
   `~/nina-restore/`, and empty the Trash. Record the date, the minutes and the
   counts in the private records; record here only the date and the minutes:

   Drills: none yet.
