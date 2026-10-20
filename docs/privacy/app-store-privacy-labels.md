# App Store Privacy Labels - Nina

Last updated: 2026-10-20

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
| Contact Info: Name | Display name: a first name for accounts created since build 11; the full name Apple shared for accounts created with builds up to 10 | App Functionality | Since build 12 Sign in with Apple asks every account for the name (`requestedScopes = [.fullName]`) and never for the email. Nina keeps only the given name Apple shares, trimmed, and never the family name, a middle name or a nickname. The sign-in sends no part of the name to the server: the given name waits on the device (protected storage, excluded from backup) until the person is named. An adult who shared it is saved with it, with no field on screen, when creating or joining a house; Apple shares a name only on an account's first authorization and the person may blank it, so when Apple gives none the adult types a first name there. A minor, or anyone whose age Apple has not shared, always confirms a first name beside the invite, prefilled with Apple's given name when there is one, so for those accounts the person is the source; the device keeps no copy once that screen appears. An adult can change the name in Perfil; a minor's screens offer no name editor. Accounts created with builds up to 10 also hold, in the Auth account's metadata, the formatted full name Apple shared then, and their profile name, and the member name any house they created or joined copied, is that full name until the person renames in Perfil; nothing rewrites the metadata. |
| Contact Info: Email Address | Email address (accounts created before build 11 only) | App Functionality | No build since 11 asks Apple for the email, so a new account carries none. An account created before build 11 keeps the email Apple shared then, which may be a private-relay address; it identifies the account and is shown read-only in the app only when present, and it is never a way to sign in. Keep the Email Address label while those accounts hold one. A minor's profile email is forced to null on the server. |
| User Content: Other User Content | Chat messages, tasks, reminders, shopping items, household members, confirmed memories, reports on a Nina reply (reason code and message reference) | App Functionality | This is the core household data. Photo and PDF reading stay off at launch (`NINA_ATTACHMENTS_ENABLED = NO`). A message held for child-safety review is sealed server-side and reachable by no client role. The profile photo is its own row below. |
| User Content: Photos or Videos | The profile photo an adult chooses for their own profile; nothing else at launch | App Functionality | Picked in Perfil, saved as a JPEG in private Storage at `profile-photos/<account id>/`, which only that account may read or write (Storage policies; uploading also needs an adult), so it appears only on that person's own phones. Removed with the account, and at once when an account becomes a minor's or unknown; a minor's screens offer no photo, and a child's or pet's profile has none. It never goes to OpenAI. The chat's "Foto" and "Documento" pickers do not exist in a build with `NINA_ATTACHMENTS_ENABLED = NO` (`NinaAttachmentGate`), and the store also drops attachments before sending; when they ship, a picture goes to OpenAI through `nina-chat` for one turn, the server keeps only its kind, file name, type and size (`attachmentMetadata`), and the phone keeps a small preview of the 12 newest; revisit this row then. The child's day shared as a picture or PDF is made on the phone and handed to the share sheet; Nina receives nothing. |
| Health & Fitness: Health | What adults write about health: tasks and reminders in the "Saúde" category (title, the optional detail line, time, owner), such as a medication or appointment reminder; health talk in the chat (kept 30 days) or in a confirmed memory; for a child or adolescent, health reminders only with the guardian's separate health consent, and the record of that consent; a report on a Nina reply may carry the reason "Saúde ou remédio" | App Functionality | Nina reads no HealthKit, clinical record or sensor and has no health field: all of it is text a person chose to write, which Apple's Health category covers. Nina answers no request for a diagnosis, symptoms, a medication choice or a dose. The server refuses a health task for a minor without a live health consent (`minor_health_consent_required`), and withdrawing that consent deletes the minor's health reminders. Prescription reading stays off with attachments. Never used for tracking or advertising, and the security basis is never applied to health data (privacy policy §7). |
| Sensitive Info | Anything else Apple counts as sensitive that adults may type in tasks, the chat or memories (pregnancy or childbirth, disability, religious belief) | App Functionality | Nothing asks for it, but people can write it. Use the conservative label; health is the row above. |
| Identifiers | Supabase Auth user ID, the Apple account identifier Supabase Auth keeps for the linked identity, family ID, invite tokens | App Functionality | Used for login, authorization, sync, and household isolation. |
| Identifiers: Device ID (UNVERIFIED category) | The App Attest key identifier and public key registered for one install and account; the access records (Marco Civil art. 15, since 2026-10-20): the IP address of each stretch of use, per account, with the date and time it started and last continued; and the IP and device type Supabase Auth keeps for each signed-in session | App Functionality, Other Purposes | The App Attest key only verifies that an age signal came from the Nina app on an iPhone, and is deleted 400 days after last use and with the account. The access records are written by the server inside `ensure_current_profile` from Cloudflare's `cf-connecting-ip` (`private.app_access_records`); uses from one address within 30 minutes merge into one record, and the source port stays empty because no header carries it. They are kept six months under seal, longer only when an authority asks (art. 15 §2) or a child-safety hold on the account is preserved, survive the account's deletion for the rest of that period, and leave only on a court order (art. 15 §3) or inside the child-safety report the law requires (Lei 15.211 art. 27). Apple names "device ID" among the types a stored IP may be declared as, and Marco Civil art. 5 III defines an IP as a terminal's identifying code; "Other Purposes" covers keeping them to answer a court order, which Apple's purpose list does not name (Heitor's choice of 2026-10-20; App Store Connect sets purposes per data type, so it covers the App Attest key too). The Auth session row goes on sign-out or account deletion. Never geolocated, logged, sent to OpenAI or used for advertising. |
| Other Data (UNVERIFIED category) | Age status (adult, minor band `under_12` / `12_15` / `16_17`, or unknown), how Apple obtained it (assurance), whether parental controls are active; guardian declarations (relationship), guardian consents, terms acceptances | App Functionality | From the Declared Age Range API through the App Attest-verified `age-signal` function. Never a birth date, never the range bounds, never a history of ranges. Guardianship and consent proof is kept 5 years after it ends, with the account link removed on deletion. |
| Usage Data: Product Interaction (UNVERIFIED category) | Minutes of use per day for a minor account | App Functionality | Collected only for claimed minors, so the guardian can see the last 7 days and set a daily limit. Kept 30 days. |
| Purchases: Purchase History | Each Premium subscription: Apple's original and latest transaction ids, the product (monthly or yearly), the environment, the status, purchase, renewal and expiry dates, the renewal state, Apple's signed transaction and renewal records and Apple's server notifications about it, bound to the buyer's account (`user_id`, and the purchase's `appAccountToken`, which is the account id) and to the house it covers | App Functionality | Written only by `premium-subscription-sync` and `app-store-server-notifications` (since 2026-09-06) into `premium_subscriptions`, `premium_subscription_transactions` and `app_store_server_notifications`; the buyer may read their own rows, and the rest of the house learns only whether it is covered. Apple sells on its own account: Nina never sees a card, a payment method or a billing address (Financial Info stays not collected). A family-shared transaction never reaches the server. On account deletion the account link is cleared (`user_id` set null) and the row stays as the house's subscription history, while Apple's signed record inside it still carries the account token. No retention period is set for these rows, and the privacy policy's retention section does not name them yet; settle both before the first public release. |
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
operation, and the given name Apple shared at sign-in waits there, with Apple's
user identifier for that app, until the person is named (removed then, on
sign-out, on account deletion, and as soon as a minor's or unknown age's screen
appears). They use opaque filenames, iOS file protection, per-entry limits, and
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
- Coarse Location (the access records' IP addresses are never turned into a region; if anything ever does, declare Coarse Location)
- Contacts
- Browsing History
- Search History
- Financial Info
- Advertising Data
- Audio Data
- Contact Info: Phone Number

**Perfil fields removed on 2026-10-15.** Builds up to 13 offered optional
"Telefone", "Sexo" and "Aniversário" fields in Perfil. The next build asks for
none of them: the app selects `profiles` by named columns that leave out
`phone`, `sex` and `birthday_label`, and a profile save no longer touches those
three columns, so no build from then on sends a phone number, a sex or a
birthday. Values typed with an earlier build remain in `profiles` until the
account is deleted or the operator's planned one-off statement clears the
columns; until then another adult of the same house can read them through the
API. Answer Phone Number "not collected" only for a binary
that carries this change, and clear the legacy values before the first public
release so the answer is also true of the server.

**Purchases, settled 2026-10-19.** This file listed Purchases as not collected
before the subscription shipped, then left the category open. The subscription
record is an account's purchase history, linked to the user, for App
Functionality, so it is the Purchase History row above. Health and Photos or
Videos were added the same day, read from the code as of that date.

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

The account's access records (Marco Civil art. 15) stay for the rest of their
six months after the deletion, and guardianship and consent proof for five
years, as the privacy policy's retention section says. Apple asks a deletion
flow that keeps data by law to say what stays; the in-app deletion sheet does
not say it yet, which needs a build (`docs/production-launch-runbook.md`, the
next-build list).

After server deletion succeeds, the app clears account-scoped household,
profile/photo, consent, onboarding, pending-invite, Apple's shared given name, and temporary-export data
using the account ID captured before Auth state is removed. In-flight local
home/profile loads are invalidated so a late response cannot recreate erased
cache files.

## Privacy Policy URL

Use:

`https://ninai.app/privacidade/`

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

`PrivacyInfo.xcprivacy` declares no `NSPrivacyCollectedDataTypes`, although
Apple's manifest documentation asks an app to list the data it collects there
too. That gap predates the access records and needs a build; whether App Store
upload checks it is UNVERIFIED.

Re-check this manifest if the app starts using file timestamps, disk space APIs, system boot time APIs, active keyboard APIs, or new SDKs with their own manifests.
