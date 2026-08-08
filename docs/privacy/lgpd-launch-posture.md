# LGPD Launch Posture - Nina

Last updated: 2026-08-03

This is an engineering/privacy operations checklist for launch readiness. It is
not a substitute for Brazilian legal review, but it documents the product
controls now present in the app and the remaining launch ownership items.

Official references:

- ANPD data subject rights:
  https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1/direito-dos-titulares
- ANPD data subject overview and DPO role:
  https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1
- LGPD official law text:
  https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- OpenAI API data controls:
  https://developers.openai.com/api/docs/guides/your-data

## Data Inventory

Nina processes:

- Account data: Supabase Auth ID, Apple identity provider metadata, linked
  email, display name.
- Profile data: role, phone, birthday label, availability, communication
  preference, memory note, avatar/photo.
- Household data: family name, invite links, participants, roles, children/pets
  entered by adults, permissions.
- Routine data: tasks, reminders, shopping items, task categories, due
  labels/dates.
- Nina data: private adult chat threads, message attachments, proposals,
  confirmed private/shared memories, household insights.
- Operational data: rate limits, AI run cost/token/latency/status metadata,
  backend request diagnostics.
- On-device diagnostics: Apple MetricKit crash, hang, launch, and performance
  payloads kept in a bounded local archive, excluded from backup and not
  uploaded automatically.
- On-device private cache: household activity, profile metadata/photo, AI
  consent, and a pending invite are stored under Application Support with
  opaque names, per-entry size limits, iOS file protection, and backup
  exclusion. Legacy `UserDefaults` values migrate only after a protected write
  succeeds.
- Launch waitlist data: normalized email, optional first name, consent version,
  locale, signup source, withdrawal time, a single-purpose cancellation
  capability, and a separate salted abuse fingerprint that expires without
  storing a raw IP address.

## Legal Bases to Validate

| Processing                                                   | Likely LGPD Basis                                        | Product Control                                                                                                  |
| ------------------------------------------------------------ | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Account, login, sync, household management                   | Contract execution / preliminary procedures              | Authenticated app account and home access.                                                                       |
| AI chat and Nina memory                                      | Consent                                                  | Consent gate before online Nina chat; revocation in Settings.                                                    |
| Security, abuse prevention, rate limits, backend diagnostics | Legitimate interest                                      | Content-free logs where possible; no ad tracking.                                                                |
| Launch notification emails                                   | Consent                                                  | Unchecked consent box, versioned consent record, cancellation link in every email, and privacy-mailbox fallback. |
| Required retention or legal requests                         | Legal obligation                                         | Policy reserves legally required retention.                                                                      |
| Health/child data entered by adults                          | Consent or other applicable basis requiring legal review | Adult-only Nina chat; data minimization copy; no child chat access.                                              |

## User Rights and Controls

Current product controls:

- Confirmation/access/export: `Ajustes -> Privacidade -> Exportar meus dados`
  generates JSON with the account, profile/photo, consent record, active home,
  and locally synchronized household data. The temporary protected export is
  replaced on regeneration and removed when the export screen closes or the
  app next launches.
- Deletion: `Ajustes -> Conta -> Apagar conta` initiates account deletion
  in-app.
- Chat deletion: `Casa -> Memórias da Nina -> Apagar meu histórico com a Nina`.
- Memory deletion/editing: memory owners can edit/delete their confirmed
  memories.
- Consent revocation: `Ajustes -> Privacidade -> Consentimento de IA`.
- Launch-email withdrawal: explicit confirmation through the private fragment
  link in each email, with the privacy mailbox as a fallback.

Operational mailbox:

- Use `oi@ninai.app` until a dedicated privacy/DPO mailbox is configured.
- Before production launch, publish the legal entity and encarregado contact on
  `/privacidade`.

Recommended request handling:

- Acknowledge privacy requests promptly.
- For LGPD access/confirmation requests, support immediate simplified response
  when possible and a complete response within the statutory window when
  required.
- Verify identity before exporting or deleting data outside the in-app
  authenticated flows.
- Log request date, requester, verified account, action taken, completion date,
  and retained exceptions.

## Retention

Implemented backend retention:

- Private Nina chat messages: 30 days by `run_nina_retention`.
- Resolved Nina proposals: 30 days.
- AI operational run logs: 90 days and content-free by design.
- Household insights: 90 days.
- Launch waitlist: 24 months from the last consent submission, or earlier after
  withdrawal.
- Waitlist abuse fingerprints: up to 24 hours and stored separately from email.
- On-device MetricKit archives: at most 12 files or 8 MB, whichever limit is
  reached first; older files are removed locally.
- On-device household/profile caches: retained for offline use while the local
  account remains present; removed on account deletion. Privacy-export files
  are temporary and removed on screen dismissal, replacement, deletion, or the
  next launch.

User-triggered deletion:

- Private chat history can be deleted immediately.
- Confirmed memories owned by the user can be deleted immediately.
- Account deletion removes profile photos, Nina content owned or authored by
  the account, household memberships, and the Auth user. Active invitations
  created by the account are revoked. Shared operational household records can
  remain for other participants without the deleted account linked, with home
  ownership transferred to a remaining claimed member.
- Database preparation is transactional and repeated inside the Auth deletion
  transaction. It is idempotent so a transient cross-service failure can be
  retried while the account still exists.
- On-device deletion uses the captured account ID after server deletion, clears
  household/profile/consent/onboarding/invite/export data, cancels local
  synchronization, and invalidates in-flight home/profile loads so late
  responses cannot recreate erased files.

## AI Processing

Current architecture:

- The iOS app never stores OpenAI API keys.
- The `nina-chat` Edge Function sends only the needed household context and
  attachments to OpenAI.
- OpenAI Responses calls use `store: false` in the backend.
- Confirmed memories are not auto-created; the user must accept a proposal.
- Personal memories start private; sharing is an explicit visibility choice.

## Launch Blockers Before Public Release

Run
`npx deno task preflight:production --env-file config/production.env
--online`
for the same release candidate. The command makes the technical and
legal-metadata items below hard failures where they can be verified
automatically. See `docs/production-launch-runbook.md` for ownership and order.

- Fill production legal entity and encarregado details on `/privacidade`.
- Confirm `oi@ninai.app` or a dedicated privacy mailbox is monitored and
  documented.
- Create a dedicated Supabase `sb_secret_...` key for the Cloudflare Worker,
  configure `NINA_SUPABASE_SECRET_KEY` and `NINA_WAITLIST_HASH_SALT` as Worker
  secrets, then confirm `/api/health` returns `200`.
- Configure a transactional email provider so every launch email includes the
  fragment-based cancellation link, recipients are selected from current
  `status = 'subscribed'` rows at send time, and provider-side scheduled sends
  honor withdrawals.
- Create the Premium subscription group and products in App Store Connect,
  deploy both subscription Edge Functions with production-only App Store
  verification, configure the Server Notifications V2 production URL, and
  confirm Apple's test notification is persisted successfully.
- Apply the transactional account-deletion migration before deploying the
  `delete-account` Edge Function. Keep its Supabase service role key only in
  function secrets, alert on stage-only failure events, and verify the shared
  home, solo home, invite, storage, and Auth deletion fixtures in staging.
- Apply all migrations, require a green database lint/pgTAP CI job, and confirm
  `nina-maintenance` runs daily with failures alerting on non-2xx responses.
- Review App Store privacy labels against the production binary and SDK list.
- Have Brazilian counsel review child/health/sensitive-data wording and legal
  bases.
