# Incident runbook

Last updated: 2026-10-19

What the operator does when something goes wrong in production: a secret
exposed, household data reaching someone it should not, the service down, or
the bill running away. A child-safety report or hold follows
`docs/child-safety-runbook.md`; restoring lost data follows
`docs/production-launch-runbook.md` §9. Secrets are named here by their
environment names only. Their values live in the platforms and in the ignored
local files (`config/production.env`, `supabase/.env.local`, `web/.dev.vars`,
`Nina/Config/SupabaseSecrets.xcconfig`), never in this repository (it is public
on GitHub), a log, an issue or a chat with an agent.

## 1. The first hour

1. **Contain before understanding.** Stop the harm with the narrowest switch
   that stops it:
   - an exposed secret: rotate it (§3), the old value revoked last;
   - the AI chat and the weekly insight, all at once: unset the key, and every
     turn answers `503 service_not_configured` before anything is stored or
     reserved, while the daily maintenance still runs its retention and
     deletions and skips the insights (`openai_not_configured`):

     ```sh
     npx supabase secrets unset OPENAI_API_KEY --project-ref apemftmlsjocvifbptum
     ```

     The phone shows "Não deu para a Nina responder agora. Tente de novo." and
     puts the words back in the composer. Set the key again to reopen (§3).
   - one account's chat: block it (`docs/child-safety-runbook.md` §3), lift it
     later with `private.operator_lift_ai_block`;
   - a function that misbehaves: deploy its last good commit from a clean
     export (`CLAUDE.md` §12), never a hand edit in the dashboard.
2. **Start the record.** The time it was seen, by whom, what was seen and each
   step taken, with times. The record is kept privately (Heitor's private
   notes), never in this repository.
3. **Assess.** Which data, whose, how many people and houses, whether children
   or adolescents are among them, whether health or a document's reading is
   involved, whether it is still happening, and whether anything reached
   OpenAI, Apple, Cloudflare or Resend that should not have.
4. **Decide who is told** (§2), within the deadline.
5. **Fix the cause, then pin it**: a test, a pgTAP assertion or a preflight
   check that fails if it returns, and a line in `CLAUDE.md` §12 or §13.

## 2. Telling the ANPD and the people

LGPD art. 48 asks the controller to tell the ANPD and the people affected of a
security incident that may bring them relevant risk or damage. Resolução
CD/ANPD nº 15/2024 (the Regulamento de Comunicação de Incidente de Segurança)
sets three working days from knowing of it, through the ANPD's own form, and
asks for a record of every incident, told or not, kept for at least five years
(read the current text before relying on these numbers: UNVERIFIED as of
2026-10-19). The controller decides; the encarregado sends the communication
and answers the ANPD.

Nina's data makes "relevant risk" the likely reading for almost any leak of
household content: it holds children's and adolescents' data, health
reminders, and private conversations. A leak of only content-free logs, or of
public keys, usually is not; write down why in the record either way.

**Reaching the people is a gap.** Accounts made since build 11 hold no email,
and the app has no message the server can push. Publish the notice on
`ninai.app` (a page the landing links to), write to the accounts that hold an
email, and ask the ANPD what else it expects. An in-app notice needs a build.

## 3. Rotating each secret

For each one: what it opens, where it lives, how to replace it, and how to
prove the new one works before the old one is revoked. Read a secret with
`read -rs NAME` and pass `"$NAME"`, then `unset NAME`, so the value never
reaches the screen or the shell history.

### Supabase

- **`NINA_SUPABASE_SECRET_KEY`** (`sb_secret_…`, the Worker's own key): reads
  and writes every table as the service role. It lives in the Worker's secrets
  and `config/production.env`. Create a new secret key in Supabase › Project
  Settings › API Keys, set it as the Worker's `NINA_SUPABASE_SECRET_KEY`
  (Cloudflare › the Worker › Settings › Variables and Secrets), update
  `config/production.env`, check that
  `curl -s -o /dev/null -w '%{http_code}\n' https://ninai.app/api/health` prints
  `200`, then delete the old key in Supabase.
- **The Edge Functions' own key** (`SUPABASE_SECRET_KEYS`, or the legacy
  `SUPABASE_SERVICE_ROLE_KEY`) is injected by the platform, never set by hand.
  If it is the one exposed, rotate it in API Keys (for the legacy JWT keys, by
  rotating the project's JWT signing key, which also replaces the legacy
  anonymous key), then send one chat turn and run one age signal to prove
  every function still answers. How fast the injected value follows is
  UNVERIFIED; watch the function logs for `service_not_configured`.
- **`NINA_SUPABASE_PUBLISHABLE_KEY`** is public by design and ships inside the
  app; RLS and the SECURITY DEFINER RPCs are the defence, not its secrecy.
  Replace it only if it is being abused: add a second publishable key, ship a
  build that carries it, expire the builds that carry the old one, and only
  then delete the old key. Deleting it first breaks every installed app at
  once.
- **The database password** (the CLI's `db push` and `db dump`): Project
  Settings › Database › reset it, and link the CLI again.
- **The personal access token** that the CLI and the Supabase MCP use: revoke
  it in the Supabase account's Access Tokens and create a new one.

### `OPENAI_API_KEY`

It bills model calls to Nina's OpenAI project; it reads nothing of Nina's,
because every call sends `store: false`. It lives in the Edge Function secrets
(`nina-chat`, `nina-maintenance`) and in `config/production.env`; the local
eval's key in `supabase/.env.local` belongs to another project. Create a key in
the production project with the same restrictions
(`docs/production-launch-runbook.md` §2, "OpenAI dashboard"), then:

```sh
read -rs OPENAI_API_KEY
npx supabase secrets set --project-ref apemftmlsjocvifbptum OPENAI_API_KEY="$OPENAI_API_KEY"
unset OPENAI_API_KEY
```

The functions read it on the next request, with no redeploy. Send one chat
turn on a test account, update `config/production.env`, then revoke the old key
in the OpenAI dashboard and check its Usage page for calls Nina did not make.

### `NINA_SAFETY_ID_SALT`

It keys the `safety_identifier` OpenAI sees for each adult. Replace it only if
it is exposed: a new salt makes every adult a new person to OpenAI's abuse
monitoring.

```sh
npx supabase secrets set --project-ref apemftmlsjocvifbptum NINA_SAFETY_ID_SALT="$(openssl rand -hex 32)"
```

A salt shorter than 32 characters refuses every turn with
`503 service_not_configured`; send one chat turn to prove it.

### Sign in with Apple key (`APPLE_SIGN_IN_PRIVATE_KEY`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_TEAM_ID`)

The `.p8` key lets the server exchange an authorization code and revoke a Sign
in with Apple token for `com.heitor.nina`; it cannot sign in as anyone. Only
the private key is secret. In Apple Developer › Certificates, Identifiers &
Profiles › Keys, create a key with Sign in with Apple for the primary App ID
`com.heitor.nina` and download it (Apple allows it once), then:

```sh
npx supabase secrets set --project-ref apemftmlsjocvifbptum APPLE_SIGN_IN_KEY_ID='<new key id>'
npx supabase secrets set --project-ref apemftmlsjocvifbptum APPLE_SIGN_IN_PRIVATE_KEY="$(cat '<path to the new .p8>')"
```

Delete a throwaway account in the app and check the `delete-account` log shows
no `apple_token_revocation_failed`; then revoke the old key in the portal.
Meanwhile deletions still complete, and only the revocation logs a failure
(the decided behaviour). Keep the new `.p8` out of this repository and out of
any synced folder, backed up privately. Whether Supabase Auth's Apple provider
also holds a secret for the web OAuth flow, which Nina does not use, is
UNVERIFIED: check Authentication › Providers › Apple, and if one is set,
replace it the same way.

### App Attest

There is no App Attest secret. Each install's key stays in its iPhone's Secure
Enclave, and the server keeps only public keys and counters
(`private.app_attest_keys`), checked against Apple's root CA embedded in
`_shared/app-attest.ts`. If forged age signals are suspected:

1. Check the mode: `npx supabase secrets list --project-ref
   apemftmlsjocvifbptum` must list `NINA_APP_ATTEST_MODE`, and the online
   preflight's `deployment.app-attest-mode` must pass.
2. Make the suspect installs attest again by removing their keys; the app
   registers once more on `app_attest_key_unknown`:

   ```sql
   delete from private.app_attest_keys where user_id = '<auth user id>';
   ```

3. Put a wrong age right only through `private.operator_set_age_status`
   (`docs/age-contest-runbook.md`). The ratchet in `record_age_signal` already
   keeps a compromised function from moving an account toward less
   protection without Apple's confirmation.

### `NINA_RESEND_API_KEY`

It sends email from the `ninai.app` domain. It lives only on the operator
machine, in `config/production.env`; Supabase's custom SMTP is off, so Auth
holds no copy (`docs/production-launch-runbook.md` §2). In Resend › API Keys,
create a sending-only key for the domain, put it in `config/production.env`,
send the test in `web/README.md`, then delete the old key. Check Supabase ›
Authentication › Emails › SMTP Settings still shows custom SMTP off.

### Cloudflare

- **`NINA_WAITLIST_HASH_SALT`** (Worker secret) keys the waitlist's abuse
  fingerprints. Replace it with `openssl rand -hex 32` in the Worker's secrets;
  the old fingerprints simply stop matching, and they expire within a day
  anyway.
- **`NINA_SUPABASE_SECRET_KEY`**: under Supabase, above.
- **The account.** Two-factor sign-in on; in My Profile › API Tokens, revoke
  any token not in use; `npx wrangler logout` on the operator Mac ends its
  local login. Check the Workers Builds connection to GitHub and the Email
  Routing rule for the privacy address: someone with the account could send
  privacy and report mail elsewhere.
- **The `PUBLIC_NINA_*` build variables are public by design**; a change to
  them is a rebuild (`docs/production-launch-runbook.md` §4), not a rotation.

### The maintenance secret

`private.nina_maintenance_config.shared_secret`, 32 random bytes. pg_cron sends
it to `nina-maintenance` in `X-Nina-Maintenance-Secret`, and the function
checks it with `verify_nina_maintenance_secret`. Whoever holds it can start a
maintenance run (retention, minor-account deletion, insights that cost money).
It lives only in the database, so no Edge Function secret changes:

```sql
update private.nina_maintenance_config
set shared_secret = encode(extensions.gen_random_bytes(32), 'hex'), updated_at = now()
where singleton;
```

The next 06:15 UTC run reads the new one. Prove it with that run's `2xx`
(`docs/production-launch-runbook.md` §8, step 8).

### Other credentials

Two-factor sign-in on the Apple Account behind App Store Connect and Apple
Developer, on GitHub (a push to `main` rebuilds the site), on the OpenAI,
Supabase and Resend accounts, and at the registrar of `ninai.app`, with its
transfer lock on. Revoke and replace any of them on suspicion.

## 4. What you may see first

| Sign | Likely cause | First move |
| --- | --- | --- |
| Every turn answers `503 service_not_configured` | `OPENAI_API_KEY` or `NINA_SAFETY_ID_SALT` missing or short | `npx supabase secrets list`, then §3 |
| Everyone gets `429 monthly_budget_reached` | the month's conversation pool is spent | read `public.nina_ai_budget_months`; raising a cap is Heitor's call (`docs/production-launch-runbook.md` §3, "The AI budget of 19 October") |
| One house gets `429 monthly_budget_reached` | that house's share of the pool is spent (`nina_budget_exceeded`) | read `private.nina_ai_household_budget_months` for the house; the share renews with the month |
| `/api/health` answers `503` | the Worker's secret or the waitlist schema constant | §3 Cloudflare; `web/README.md` |
| Every Apple receipt fails verification | the chain check or Apple's roots | `_shared/apple-jws.ts`; never reintroduce `SignedDataVerifier` (`CLAUDE.md` §12) |
| A log line carries a message, a name or an age | a logging regression | contain, then the content-free log tests in `nina-ai.test.ts` |
| A person sees another house's data | an RLS or grant regression | contain at once (revoke the grant or policy), then §2: it is an incident to report |
| The site reads `data-legal-status="incomplete"` | a build without the legal variables | rebuild through Cloudflare from git (`CLAUDE.md` §13) |

## 5. After

Close the record with the cause, the fix, who was told and when. Add the test
or check that pins the fix, update `CLAUDE.md` where the trap belongs, and if
the incident changed what the privacy policy or the Terms say is true, change
them in the same release.
