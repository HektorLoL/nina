# Nina Production Launch Runbook

Last updated: 2026-08-03

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
credential patterns, protected local-data and erasure invariants,
legal-metadata wiring, and CI enforcement. It never prints credential values.
CI runs the same gate on every pull request and push to `main`.

## 2. Prepare the release environment

Copy `config/production.env.example` to the ignored `config/production.env` and
replace every placeholder. Keep the file local. It is an inventory for
preflight, not a provider-specific upload file.

Distribute only the relevant values:

| Destination                    | Values                                                                                                                                                |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| iOS release xcconfig           | `NINA_SUPABASE_URL`, `NINA_SUPABASE_PUBLISHABLE_KEY`, `NINA_AI_V2_ENABLED`                                                                            |
| Cloudflare Worker runtime      | `NINA_SUPABASE_URL`, `NINA_SUPABASE_PUBLISHABLE_KEY`, `NINA_SUPABASE_SECRET_KEY`, `NINA_WAITLIST_HASH_SALT`                                           |
| Astro production build         | All `PUBLIC_NINA_*` values                                                                                                                            |
| Supabase Edge Function secrets | `OPENAI_API_KEY`, `NINA_APP_BUNDLE_ID`, `NINA_APP_APPLE_ID`, `NINA_PREMIUM_PRODUCT_IDS`, `NINA_APP_STORE_ENVIRONMENT`, `NINA_APP_STORE_ONLINE_CHECKS` |
| Release records only           | `NINA_APPLE_TEAM_ID`, `NINA_PUBLIC_BASE_URL`                                                                                                          |

Do not upload the complete inventory to any one platform. In particular, never
place `NINA_SUPABASE_SECRET_KEY` or `OPENAI_API_KEY` in an Astro `PUBLIC_*`
variable, Xcode setting, app plist, or client bundle.

Validate the inventory before deployment:

```sh
npx deno task preflight:production --env-file config/production.env
```

The command checks key roles without printing keys, requires a production App
Store verifier, compares product/team/bundle identifiers with source control,
and fails on incomplete controller, DPO, or mailbox values.

## 3. Database and Edge Functions

Use a separate staging Supabase project first. Apply migrations in order, then
run:

```sh
npx supabase db lint --linked --fail-on error
npx supabase test db --linked
```

Deploy `nina-chat`, `nina-maintenance`, `delete-account`,
`premium-subscription-sync`, and `app-store-server-notifications`. Schedule
`nina-maintenance` daily and alert on timeout, non-2xx response, or missed run.

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
- subscription purchase, restore, renewal, expiration, cancellation, and
  billing-retry states synchronize correctly.

For the deletion staging exercise, use accounts created only for the test. Run
the in-app flow with a solo owner and with a shared-home owner, then verify the
Auth user and `profile-photos/<user-id>` objects are gone. Verify the shared
home has a remaining owner, no invite retains the deleted UUID, and shared
records that survive have nullable creator references cleared. Function failure
logs may contain the request ID and stage only, never the user ID, bearer token,
request body, or raw upstream error.

## 4. Website deployment

Provide the five `PUBLIC_NINA_*` values to the Astro build environment. Build
before deploying so `/privacidade` contains the final controller and DPO
identity. Configure the Worker public values and its two secrets separately.

After Cloudflare deploys `https://ninai.app`, run:

```sh
npx deno task preflight:production --env-file config/production.env --online
```

Online mode performs read-only probes of the landing page, security headers,
`/api/health`, privacy metadata, unsubscribe indexing policy, and the AASA file.
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

Run the release candidate through TestFlight on at least one current iPhone and
one supported older device. Exercise:

- first launch, Apple sign-in, OTP fallback, sign-out, and session restoration;
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
  retry, and server-notification delay.

Record the tested build number, devices, OS versions, tester, date, and result.
Do not promote a different build number without rerunning the affected gates.

For the same release build, inspect a development-signed app container on a
physical device after first unlock. Confirm private-cache and privacy-export
files have `NSFileProtectionCompleteUntilFirstUserAuthentication`, use opaque
names, enforce the documented size bounds, and carry the backup-exclusion
resource flag. Simulator tests may verify writes and backup exclusion, but do
not treat missing simulator file-protection metadata as physical-device proof.

## 6. Human approvals

The technical gate cannot substitute for these approvals:

- Brazilian counsel approves the policy, legal bases, child/sensitive-data
  wording, controller identity, and DPO details.
- The privacy mailbox has a named owner and a tested response procedure.
- App Store privacy labels match the submitted binary and production operators.
- Transactional email has SPF, DKIM, DMARC, consent-at-send filtering, the Nina
  unsubscribe fragment link, and provider-side suppression synchronization.
- On-call ownership exists for website health, Edge Functions, database
  maintenance, subscription notifications, AI budget, and crash diagnostics.
