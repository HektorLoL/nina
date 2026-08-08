# App Store Privacy Labels - Nina

Last updated: 2026-08-03

Use this as the App Store Connect privacy questionnaire source of truth for the current codebase. Re-check it before every submission because labels must match the shipped binary, backend functions, SDKs, and website data collection.

Official references:

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- App Store Connect privacy management: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Apple account deletion requirement: https://developer.apple.com/support/offering-account-deletion-in-your-app/

## Tracking

Nina does not track users across apps or websites owned by other companies.

Recommended answer:

- Data Used to Track You: `No`
- Third-party advertising: `No`
- Data broker sharing: `No`

## Data Linked to the User

These categories are linked to a user account, family, or household context.

| Apple Category | Nina Data | Purposes | Notes |
| --- | --- | --- | --- |
| Contact Info | Email address, display name | App Functionality, Account Management | Email is used for OTP login and account/profile support. |
| User Content | Chat messages, tasks, reminders, shopping items, household members, profile photo, document/image attachments, confirmed memories | App Functionality | This is the core household data. |
| Sensitive Info | Health hints, medication/school/child routine details, emotional pattern notes when users enter them | App Functionality | The app does not require these fields, but users can submit them in messages/documents/memories. Use the conservative label. |
| Identifiers | Supabase Auth user ID, family ID, invite tokens | App Functionality, Account Management | Used for login, authorization, sync, and household isolation. |
| Diagnostics | Backend operation metadata, AI run status/cost/token metadata, rate-limit counters | App Functionality, Analytics | Operational logs should remain content-free. If additional analytics SDKs are added, update this row. |

The website launch waitlist separately collects an email address, optional
first name, consent metadata, locale, and signup source. This website collection
does not change the iOS binary's App Store privacy answers, but it must remain
covered by the public privacy policy.

The iOS app also keeps a bounded Apple MetricKit archive on the device for
crashes, hangs, launch diagnostics, and performance reports. These files are
excluded from backup and are not transmitted automatically, so they are not
off-device collection for App Store privacy-label purposes.

Household activity, profile metadata/photo, AI consent, and pending-invite
caches also remain on device for offline operation. They use opaque filenames,
iOS file protection, per-entry limits, and backup exclusion. This local-only
storage does not change the collection answers above; synchronized copies sent
to Nina's backend remain covered by the linked-data rows.

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
- Purchases
- Financial Info
- Advertising Data
- Audio Data

If voice input, payments, subscription receipts, crash SDKs, ad attribution, or analytics SDKs are added, update this file and App Store Connect before release.

## Account Deletion

The app includes an in-app deletion path:

`Ajustes -> Conta -> Apagar conta`

Deletion requires an explicit in-app confirmation and calls the authenticated
`delete-account` Supabase Edge Function. The function removes profile photo
storage, Nina content owned or authored by the account, household membership,
and the Supabase Auth user. Active invitations created by the account are
revoked. In shared homes, operational household records can remain for other
members with the deleted account identifier unlinked and ownership transferred
to a remaining member. The database preparation is transactional and
idempotent, so a failed final Auth call can be retried without duplicating or
corrupting household state.

After server deletion succeeds, the app clears account-scoped household,
profile/photo, consent, onboarding, pending-invite, and temporary-export data
using the account ID captured before Auth state is removed. In-flight local
home/profile loads are invalidated so a late response cannot recreate erased
cache files.

## Privacy Policy URL

Use:

`https://ninai.app/privacidade`

Before submission, confirm the deployed page contains the production legal entity and privacy contact.

## Privacy Manifest

The app target includes `Nina/PrivacyInfo.xcprivacy`.

Current required-reason API declaration:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, because Nina
  stores app preferences, onboarding state, and notification settings there.
  Reads of older consent/invite/profile/household values exist only for the
  one-time migration into protected, backup-excluded files; the legacy value is
  removed only after that write succeeds.

Re-check this manifest if the app starts using file timestamps, disk space APIs, system boot time APIs, active keyboard APIs, or new SDKs with their own manifests.
