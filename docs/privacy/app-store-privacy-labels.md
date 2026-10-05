# App Store Privacy Labels - Nina

Last updated: 2026-10-04

Use this as the App Store Connect privacy questionnaire source of truth for the current codebase. Re-check it before every submission because labels must match the shipped binary, backend functions, SDKs, and website data collection.

Official references:

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- App Store Connect privacy management: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Apple account deletion requirement: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple Developer Program License Agreement §3.3.3(O), which limits Declared Age Range data to age-appropriate features and legal compliance: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/

## Tracking

Nina does not track users across apps or websites owned by other companies.

Recommended answer:

- Data Used to Track You: `No`
- Third-party advertising: `No`
- Data broker sharing: `No`

The age band from Declared Age Range, the assurance method, the App Attest key,
and a minor's minutes of use are never combined with third-party data, never
sent to OpenAI, never written to logs, and never used for advertising. The
license agreement forbids any use of the age range beyond age-appropriate
features and legal compliance, so these rows can never move to tracking.

## Data Linked to the User

These categories are linked to a user account, family, or household context.

Rows marked UNVERIFIED use the Apple category that reads closest to the data.
Apple's documentation names no category for an age range, a guardianship record,
or an attestation key; confirm the choice in App Store Connect before
submission and record the answer here.

| Apple Category | Nina Data | Purposes | Notes |
| --- | --- | --- | --- |
| Contact Info | Email address (accounts created before build 11 only), display name | App Functionality, Account Management | Since build 11 Sign in with Apple asks no account for a name or an email, so a new account carries no email; the display name is the first name the person types when creating or joining a house, editable in Perfil. An account created before build 11 keeps the email Apple shared then, which may be a private-relay address; it identifies the account and is shown read-only in the app only when present, and it is never a way to sign in. Keep the Email Address label while those accounts hold one. A minor's profile email is forced to null on the server. |
| User Content | Chat messages, tasks, reminders, shopping items, household members, profile photo, confirmed memories, reports on a Nina reply (reason code and message reference) | App Functionality | This is the core household data. Photo and PDF reading stay off at launch (`NINA_ATTACHMENTS_ENABLED = NO`). A message held for child-safety review is sealed server-side and reachable by no client role. |
| Sensitive Info | Health hints, medication/school/child routine details, emotional pattern notes when users enter them; health reminders of a child or teen when a guardian gave the separate health consent | App Functionality | The app does not require these fields, but adults can enter them in messages and memories. Use the conservative label. |
| Identifiers | Supabase Auth user ID, the Apple account identifier Supabase Auth keeps for the linked identity, family ID, invite tokens | App Functionality, Account Management | Used for login, authorization, sync, and household isolation. |
| Identifiers: Device ID (UNVERIFIED category) | The App Attest key identifier and public key registered for one install and account | App Functionality | Used only to verify that an age signal came from the Nina app on an iPhone. Deleted 400 days after last use and with the account. |
| Other Data (UNVERIFIED category) | Age status (adult, minor band `under_12` / `12_15` / `16_17`, or unknown), how Apple obtained it (assurance), whether parental controls are active; guardian declarations (relationship), guardian consents, terms acceptances | App Functionality | From the Declared Age Range API through the App Attest-verified `age-signal` function. Never a birth date, never the range bounds, never a history of ranges. Guardianship and consent proof is kept 5 years after it ends, with the account link removed on deletion. |
| Usage Data: Product Interaction (UNVERIFIED category) | Minutes of use per day for a minor account | App Functionality | Collected only for claimed minors, so the guardian can see the last 7 days and set a daily limit. Kept 30 days. |
| Diagnostics | Backend operation metadata, AI run status/cost/token metadata, rate-limit counters | App Functionality, Analytics | Operational logs should remain content-free. Age, band and assurance never enter a log line. If additional analytics SDKs are added, update this row. |

The website launch waitlist separately collects an email address, optional
first name, consent metadata, locale, and signup source. This website collection
does not change the iOS binary's App Store privacy answers, but it must remain
covered by the public privacy policy. The public report channel on
`/denuncia/` is an email address; the website collects nothing from it.

The iOS app also keeps a bounded Apple MetricKit archive on the device for
crashes, hangs, launch diagnostics, and performance reports. These files are
excluded from backup and are not transmitted automatically, so they are not
off-device collection for App Store privacy-label purposes.

Household activity, profile metadata/photo, AI consent, pending-invite caches,
and a minor's running usage counter also remain on device for offline
operation. They use opaque filenames, iOS file protection, per-entry limits, and
backup exclusion. The App Attest key identifier lives in the Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in `UserDefaults`.
This local-only storage does not change the collection answers above;
synchronized copies sent to Nina's backend remain covered by the linked-data
rows.

## Data Not Linked to the User

Do not claim data is not linked unless the production observability stack confirms it cannot reasonably be tied to an account, device, IP, or family.

Current recommendation: leave this section empty.

## Data Not Collected

Current code does not intentionally collect:

- Precise Location
- Coarse Location
- Contacts
- Browsing History
- Search History
- Financial Info
- Advertising Data
- Audio Data

Re-check before submission: **Purchases.** Since 2026-09-06
`premium-subscription-sync` and `app-store-server-notifications` store each
subscription's original transaction, product, status and expiry, bound to the
buyer's account. Apple's "Purchases" category ("an account's or individual's
purchases or purchase tendencies") very likely covers that record, linked to the
user, for App Functionality. This file listed Purchases as not collected before
the subscription shipped; the category choice is UNVERIFIED and must be settled
in App Store Connect.

If voice input, payments, crash SDKs, ad attribution, or analytics SDKs are added, update this file and App Store Connect before release.

## Account Deletion

The app includes an in-app deletion path:

`Ajustes -> Conta -> Apagar conta`

The same deletion flow is reachable from every signed-in state without a house:
no house yet, a pending request, a declined or removed request, an unavailable
house, and every state of a minor account. A person never has to join a house
to be able to delete their account.

When the person has their own active auto-renewing subscription, the deletion
screen says, above the confirmation, that deleting the account does not cancel
the Apple billing and links to Apple's subscription management. Terms §8 says
the same.

Deletion requires an explicit in-app confirmation and calls the authenticated
`delete-account` Supabase Edge Function. The function removes profile photo
storage, Nina content owned or authored by the account, household membership,
and the Supabase Auth user. Active invitations created by the account are
revoked. In shared homes, operational household records can remain for other
members with the deleted account identifier unlinked and ownership transferred
to a remaining adult member. The database preparation is transactional and
idempotent, so a failed final Auth call can be retried without duplicating or
corrupting household state.

For an account that signed in with Apple, the app asks Apple for a fresh
authorization code at deletion time. After the Auth user is deleted, the
function exchanges that code and calls Apple's `/auth/revoke`, so the Sign in
with Apple link ends too. Revocation runs last so it can never block or undo a
deletion; a failure is logged content-free (`apple_token_revocation_failed`
with a stage code only) and the deletion still reports success. Cancelling the
Apple sheet cancels the deletion; any other Apple failure deletes without
revocation.

A live guardian can delete a claimed minor's account from the minor's screen.
That path has no Apple authorization code, so the minor's Sign in with Apple
link is not revoked; the minor can end it in their Apple Account settings. A
minor account left without a house for 30 days is deleted by
`nina-maintenance` through the same photos, preparation and Auth order.

After server deletion succeeds, the app clears account-scoped household,
profile/photo, consent, onboarding, pending-invite, and temporary-export data
using the account ID captured before Auth state is removed. In-flight local
home/profile loads are invalidated so a late response cannot recreate erased
cache files.

## Privacy Policy URL

Use:

`https://ninai.app/privacidade`

Before submission, confirm the deployed page contains the production legal
entity and privacy contact, and that `data-legal-launch="ready"` (a company
with a CNPJ, an address, and an encarregado who is not the controller).

The age-rating section of App Store Connect takes a separate Age Suitability
URL: `https://ninai.app/familias/`. The questionnaire answers and their
rationale are in `docs/privacy/classificacao-indicativa.md`.

## Privacy Manifest

The app target includes `Nina/PrivacyInfo.xcprivacy`.

Current required-reason API declaration:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, because Nina
  stores app preferences, onboarding state, and notification settings there.
  Reads of older consent/invite/profile/household values exist only for the
  one-time migration into protected, backup-excluded files; the legacy value is
  removed only after that write succeeds.

App Attest and the Keychain are not on Apple's required-reason API list.
Whether the Declared Age Range framework needs a manifest entry is UNVERIFIED;
check the list again when archiving the first build that links it.

Re-check this manifest if the app starts using file timestamps, disk space APIs, system boot time APIs, active keyboard APIs, or new SDKs with their own manifests.
