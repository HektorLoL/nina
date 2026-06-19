# App Store Privacy Labels - Nina

Last updated: 2026-06-16

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

Deletion calls the authenticated `delete-account` Supabase Edge Function. The function removes private Nina content, profile photo storage, account membership, and the Supabase Auth user. In shared homes, household records can remain for other members with the deleted account unlinked.

## Privacy Policy URL

Use:

`https://ninai.app/privacidade`

Before submission, confirm the deployed page contains the production legal entity and privacy contact.

## Privacy Manifest

The app target includes `Nina/PrivacyInfo.xcprivacy`.

Current required-reason API declaration:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, because Nina stores app/user preferences, consent state, onboarding status, invite state, local profile cache, and local household cache.

Re-check this manifest if the app starts using file timestamps, disk space APIs, system boot time APIs, active keyboard APIs, or new SDKs with their own manifests.
