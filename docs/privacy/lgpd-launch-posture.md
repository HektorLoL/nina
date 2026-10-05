# LGPD Launch Posture - Nina

Last updated: 2026-10-05

This is an engineering/privacy operations checklist for launch readiness. It is
not a substitute for Brazilian legal review, but it documents the product
controls now present in the app and the remaining launch ownership items. Since
2026-09-29 Nina has no minimum age: the regime for children and adolescents is
in "Minors" below, the full assessment is in
`docs/privacy/avaliacao-impacto-criancas.md`, and the record of processing is
`docs/privacy/registro-de-operacoes.md`.

Official references:

- ANPD data subject rights:
  https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1/direito-dos-titulares
- ANPD data subject overview and DPO role:
  https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1
- LGPD official law text:
  https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- Lei 15.211/2025 (ECA Digital), in force since 2026-03-17:
  https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2025/lei/L15211.htm
- Decreto 12.880/2026, which regulates it:
  https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2026/decreto/d12880.htm
- Res. CD/ANPD 19/2024 (international transfers) and Res. CD/ANPD 18/2024
  (the encarregado), both under
  https://www.gov.br/anpd/pt-br/acesso-a-informacao/institucional/atos-normativos/regulamentacoes_anpd
- OpenAI API data controls:
  https://developers.openai.com/api/docs/guides/your-data

## Data Inventory

Nina processes:

- Account data: Supabase Auth ID, Apple identity provider metadata, display
  name (the first name the person types), and, only for an account created
  before build 11, the email Apple shared at sign-in (a private-relay address
  when the person hid theirs). Since build 11 Sign in with Apple asks no
  account for a name or an email.
- Age data: one row per account with status (`adult`, `minor`, `unknown`), the
  minor band (`under_12`, `12_15`, `16_17`), the assurance method
  (`confirmed`, `self_declared`, `guardian_declared`, `operator`, `none`), a
  parental-controls flag, and the next recheck date. Never a birth date, never
  the range bounds, never a history. It is written only by the service-role
  `record_age_signal`, reached through the App Attest-verified `age-signal`
  function.
- Device attestation: one App Attest key identifier, public key and counter
  per install and account, plus short-lived single-use challenges.
- Profile data: role, phone, birthday label, availability, communication
  preference, memory note, avatar/photo. For an account whose effective status
  is minor, the server forces email to null and every optional field to empty.
- Household data: family name, invite links, participants, roles, children,
  teens and pets, permissions. Child and teen rows carry no birth date and no
  photo.
- Minors' records: a minor profile per child or teen member (declared band,
  optional nicknames, supervision settings), guardianships (relationship,
  consent text version, guardian assurance, start and end), consents per
  purpose (`account`, `profile`, `health`), terms acceptances (who accepted,
  and whether on the minor's behalf or jointly), a minor's acknowledgement of
  the first-run text, and minutes of use per day.
- Routine data: tasks, reminders, shopping items, task categories, due
  labels/dates.
- Nina data: private adult chat threads, proposals, confirmed private/shared
  memories, household insights. Photo and PDF attachments stay off at launch.
- Safety data: reports on a Nina reply (reason code and message reference), AI
  blocks per account, and child-safety holds (the sealed text of a message the
  moderation flagged as sexual content involving minors).
- Operational data: rate limits, AI run cost/token/latency/status metadata,
  backend request diagnostics.
- On-device diagnostics: Apple MetricKit crash, hang, launch, and performance
  payloads kept in a bounded local archive, excluded from backup and not
  uploaded automatically.
- On-device private cache: household activity, profile metadata/photo, AI
  consent, a pending invite, and a minor's running usage counter are stored
  under Application Support with opaque names, per-entry size limits, iOS file
  protection, and backup exclusion. The App Attest key identifier lives in the
  Keychain. Legacy `UserDefaults` values migrate only after a protected write
  succeeds.
- Launch waitlist data: normalized email, optional first name, consent version,
  locale, signup source, withdrawal time, a single-purpose cancellation
  capability, and a separate salted abuse fingerprint that expires without
  storing a raw IP address.

## Legal Bases to Validate

| Processing | Likely LGPD Basis | Product Control |
| --- | --- | --- |
| Account, login, sync, household management | Contract execution / preliminary procedures | Authenticated app account and home access. |
| Age band and assurance | Legal obligation (art. 7 II; Lei 15.211 art. 14) | Single purpose (Lei 15.211 art. 13): feature gating only; never in AI context, insights, logs or anyone else's export. |
| Minor account, child or teen profile | Specific, highlighted consent of a parent or legal guardian (art. 14 §1) | Guardian sheet with a declaration, a separate consent checkbox and a recorded text version; only an Apple-confirmed adult can give it. |
| Health reminders of a minor | Specific consent of the guardian (arts. 11 I and 14 §1) | Separate optional checkbox; enforced server-side by `tasks_minor_health_guard` at `category_id = 'health'`; withdrawable. |
| AI chat, Nina memory, weekly insight | Consent (art. 7 I) | Server-recorded consent per adult in `nina_ai_consents` at the current version, enforced inside `begin_nina_chat_run` and `get_nina_weekly_candidates`; withdrawn grants are retained as a demonstrable record. |
| Transfer to OpenAI in the United States | Specific, highlighted consent to the transfer (art. 33 VIII) | Separate required checkbox on the consent card, recorded as `transfer_consented_at`; a grant without it is refused. |
| Security, abuse prevention, rate limits, backend diagnostics | Legitimate interest, never for health data | Content-free logs; no ad tracking. |
| Reports and child-safety holds | Legal obligation (Lei 15.211 art. 27; Decreto 12.880 art. 39) | Sealed table no client role reaches; runbook `docs/child-safety-runbook.md`. |
| Launch notification emails | Consent | Unchecked consent box, versioned consent record, cancellation link in every email, and privacy-mailbox fallback. |
| Required retention or legal requests | Legal obligation | Policy reserves legally required retention. |

The adult's own health text that reaches OpenAI through the chat rests on the
same consent as the chat. Whether that consent is specific enough for
sensitive data under art. 11 I is a residual risk nobody has reviewed.

## AI Consent, version 2026-09-29

The consent the app recorded before 2026-09-29 was given on text that said
nothing sent to the model is kept. OpenAI's data controls say abuse-monitoring
logs are kept for up to 30 days, or longer if the law requires, so those
consents rested on inaccurate information (LGPD art. 9 §1). Migration
`202609290006_ai_gates.sql` withdraws every live consent with
`revoke_reason = 'policy_changed'` and keeps the rows as records. Every adult
accepts again.

The new consent:

- names OpenAI, a company in the United States, and says that what the person
  writes and the house details Nina needs (tasks, shopping, names) are sent;
- says OpenAI may keep what is sent for up to 30 days to prevent abuse, or
  longer if the law requires, and does not train on it;
- says children's and adolescents' names go as a code and their tasks never go;
- carries a separate, unchecked, required checkbox for the transfer abroad
  (LGPD art. 33 VIII, "distinguindo claramente esta de outras finalidades");
- is recorded at `PrivacyPolicyVersion.current = "2026-09-29"`, which equals
  `private.age_policy.current_policy_version`. An older stored version counts as
  no consent, and the card shows "Este aviso mudou.";
- can be given only by an adult the server may let use the AI: effective status
  adult, no active parental controls, and an assurance inside
  `private.age_policy.trusted_assurances`, which defaults to `confirmed` and
  `operator` (decision D3, 2026-09-29).

`trusted_assurances` is the operator switch that may later admit
`self_declared` adults to chat and Premium only. It never widens who may act for
a minor, which stays hard-coded to `confirmed` and `operator`. The TestFlight
distribution of assurance levels is read with
`private.age_assurance_distribution()` before deciding. Terms §4 and privacy §5
say the chat and Premium need an adult whose age Apple confirmed; widening the
switch makes that false, so both pages change in the same release.

## Minors

Decided 2026-09-29 (D1): Nina aims for the "Livre" rating; if Apple or the
Ministério da Justiça assign 10 or 12, the app keeps the AI chat for adults and
changes the one rating constant. The regime:

- **No minimum age in the Terms.** Adult-only features are named; age comes from
  Apple's Declared Age Range (iOS 26.4 and later), recorded only through an App
  Attest-verified endpoint. Unknown age is treated as the youngest band.
- **A minor enters a house only through a guardian's approval** by an owner or
  admin whose adult age Apple confirmed, with a declaration of being mother,
  father or legal guardian, and the `account` consent, written atomically. An
  unknown requester approved this way becomes a minor with the band the
  guardian declared.
- **Child and teen profiles** are created only by an Apple-confirmed adult with
  the same declaration and the `profile` consent. Profiles created before
  2026-09-29 without a guardian are deleted after
  `private.age_policy.legacy_profile_deadline`.
- **A minor account holds no table access.** It reads only its own tasks (title,
  time, glyph) through `get_minor_home_view` and writes only through
  `set_minor_task_done`, `record_minor_usage` and `acknowledge_minor_terms`. No
  chat, no purchases, no shopping list, no other member.
- **Supervision** defaults to the most protective settings (Lei 15.211 art. 17
  §4): quiet hours on from 21:00 to 07:00, a 30-minute daily limit, alerts on,
  no follow-up nudges. The guardian sees the last 7 days of use and can export
  or delete the minor's data.
- **Nothing about a minor reaches OpenAI by name.** Every model-bound string is
  pseudonymized; minors' tasks are excluded from every tool; minors are never
  insight carriers or portrait carriers.
- **Terms acceptance**: a guardian accepts on behalf of a minor under 16, and
  jointly with a minor of 16 or 17 (Código Civil arts. 3 and 1.634 VII).
- **Majority** moves a minor to adult only on an Apple `confirmed` signal or an
  operator decision; the guardianship then ends with `reached_majority` and the
  person accepts the Terms themselves.

## User Rights and Controls

Current product controls:

- Confirmation/access/export: `Ajustes -> Privacidade e dados` exports the
  person's own data, built on the server by `export_account_data()` (their
  account, profile, age record, memberships, tasks and shopping they own or
  wrote, their Nina messages, memories and proposals, their consents and
  acceptances, guardianships they hold, their premium records). It never
  includes another member's birth date, memory note or age. The temporary
  protected export file is replaced on regeneration and removed when the export
  screen closes or the app next launches.
- A live guardian exports a minor's data from the minor's screen
  (`export_minor_data`, LGPD art. 18 §3).
- Deletion: `Ajustes -> Conta -> Apagar conta`, reachable from every signed-in
  state, including no house, a pending or refused request, an unavailable
  house, and every minor state.
- Chat deletion: `Casa -> Memórias da Nina -> Apagar meu histórico com a Nina`.
- Memory deletion/editing: memory owners can edit/delete their confirmed
  memories.
- Consent revocation: `Ajustes -> Privacidade e dados`, effective immediately
  for the chat and the weekly insight.
- Age contest (Decreto 12.880 art. 27): share the band again from the app, ask
  the guardian who declared it, or write to the privacy mailbox; the operator
  resolves it with `private.operator_set_age_status`
  (`docs/age-contest-runbook.md`).
- Reports: "Denunciar um problema" (every account) opens an identified email with
  the subject "Denúncia ECA Digital"; adults can also report a Nina reply in the
  chat. The public explanation is `https://ninai.app/denuncia/`.
- Launch-email withdrawal: explicit confirmation through the private fragment
  link in each email, with the privacy mailbox as a fallback.

Operational mailboxes:

- Privacy requests: `privacidade@ninai.app` (`PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`).
- Reports: `PUBLIC_NINA_REPORT_CONTACT_EMAIL`, which falls back to the privacy
  mailbox and is set to the same address until a dedicated report mailbox
  exists.
- `/denuncia/` promises an acknowledgement within 48 hours. That number is
  Heitor's choice; the law sets none.

Recommended request handling:

- Acknowledge privacy requests promptly.
- For LGPD access/confirmation requests, support immediate simplified response
  when possible and a complete response within 15 days (art. 19 II), which the
  privacy policy promises for requests about minors.
- Verify identity before exporting or deleting data outside the in-app
  authenticated flows.
- A deletion request mailed from the app's way-out (a refusal, or a second
  failure in a row, on "Apagar conta") carries only references: "Referência:
  ‹auth user id›", or a ward's member id plus "Responsável: ‹guardian's auth
  user id›". Build-11 accounts and minors have no email, so the reference is how
  the account is found, and it proves nothing: other adults of the house can
  read it. There is no sender address to check either. Follow
  `docs/production-launch-runbook.md` §2, "Deletion requests by mail": the
  sender proves control from inside the account (a one-time code the operator
  mails, typed as the Perfil name and read back from `profiles`), a guardian
  proves their own account and passes `authorize_guardian_account_deletion`, a
  minor's or unknown-age account's own mail is never acted on alone, then the
  profile photos and the Auth user are deleted (the database trigger runs the
  same preparation as the app) and the request is logged with the proof used.
- An age contest mailed from "Minha idade está errada" carries "Referência:
  ‹auth user id›" the same way, and the same proof rules hold before any move
  (`docs/age-contest-runbook.md`).
- Log request date, requester, verified account and the proof that verified it,
  action taken, completion date, and retained exceptions.

## Retention

Implemented backend retention:

- Private Nina chat messages: 30 days by `run_nina_retention`. A message
  reported for review is held up to 90 days.
- Resolved Nina proposals: 30 days.
- AI operational run logs: 90 days and content-free by design.
- Household insights: 90 days.
- Age signal challenges: 1 day. App Attest keys: 400 days after last use.
- Minors' pending join requests: 7 days. Minor accounts without a house: deleted
  after 30 days by `nina-maintenance`.
- Minors' usage minutes: 30 days.
- Reviewed reply reports: 6 months. Lifted AI blocks: 1 year.
- Guardianship, consent and acceptance proof: 5 years after it ends, with the
  user id nulled on deletion and the salted hash kept (LGPD art. 8 §2 burden of
  proof).
- Child-safety holds: sealed until the Polícia Federal confirms receipt, then
  deleted; account data and metadata kept for the period Lei 15.211 art. 27 §2
  requires.
- Launch waitlist: 24 months from the last consent submission, or earlier after
  withdrawal.
- Waitlist abuse fingerprints: up to 24 hours and stored separately from email.
- On-device MetricKit archives: at most 12 files or 8 MB, whichever limit is
  reached first; older files are removed locally.
- On-device household/profile caches: retained for offline use while the local
  account remains present; removed on account deletion. Privacy-export files
  are temporary and removed on screen dismissal, replacement, deletion, or the
  next launch.
- At OpenAI: abuse-monitoring logs up to 30 days, or longer if the law requires
  (OpenAI data controls). Nina has no Zero Data Retention agreement.

User-triggered deletion:

- Private chat history can be deleted immediately.
- Confirmed memories owned by the user can be deleted immediately.
- Account deletion removes profile photos, Nina content owned or authored by
  the account, household memberships, and the Auth user. Active invitations
  created by the account are revoked. Shared operational household records can
  remain for other participants without the deleted account linked, with home
  ownership transferred to a remaining adult member.
- For a Sign in with Apple account, deletion then asks Apple to revoke the
  account's token (`/auth/revoke`), after the Auth user is gone, so it never
  blocks the deletion. A guardian's deletion of a ward has no Apple code and
  revokes nothing; that gap is documented.
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
- The `nina-chat` Edge Function sends only the needed household context to
  OpenAI, after pseudonymizing every model-bound string: children become
  "Criança N", teens "Adolescente N", claimed members of unknown age
  "Pessoa N", other adults without a live consent "Adulto N", and the family
  name "Casa". An adult whose name holds a minor's name gets an "Adulto N"
  code of their own, and structured fields (workload, owner labels, member
  context) are named from the member id, so an adult's work is never shown as
  a minor's. The moderation input and the token pre-count take the same
  pseudonymized body. Minors' tasks and shopping items never reach any tool.
- OpenAI Responses calls use `store: false` in the backend. OpenAI still keeps
  abuse-monitoring logs for up to 30 days; no Nina surface may claim otherwise
  (preflight `repository.retention-claims`).
- Calls on `gpt-6-luna` (the chat turn and the weekly insight) also send
  `prompt_cache_options: { mode: "explicit" }` with no breakpoint, so no prompt
  is written to OpenAI's prompt cache. Left at its default, that model caches
  the whole prompt, household context included, for at least 30 minutes and
  possibly longer. The `gpt-5.4-mini` insight fallback does not accept the
  parameter and keeps that model's in-memory prompt cache, which OpenAI
  describes as typically 5 to 10 minutes and at most one hour.
- Every call carries a `safety_identifier`, a salted hash of the user id, never
  logged.
- The reply and the proposal text pass output moderation; a flagged turn
  becomes a fixed refusal. Requests for diagnosis, symptoms, medication or dose,
  and any change of dose, get a deterministic refusal that points to a health
  professional. A message moderation flags for self-harm gets a fixed reply with
  the CVV line (188) and never reaches the model; any other refused message is
  kept on the server only as "Mensagem não enviada.".
- An input flagged as sexual content involving minors is not stored in the
  normal message table, is sealed in `private.child_safety_holds`, and blocks
  the account's chat until the operator reviews it. Deleting that account
  first seals a copy of its identifiers and data in
  `private.child_safety_preserved_accounts` for the preservation period
  (Decreto 12.880 art. 39 §§1–2).
- The weekly insight carries only claimed adults with a live, current,
  transfer-consented consent, and is skipped with fewer than 2 such carriers.
- Confirmed memories are not auto-created; the user must accept a proposal.
- Personal memories start private; sharing is an explicit visibility choice.

The transfer abroad is published in the privacy policy §6A (Res. CD/ANPD
19/2024, Anexo I art. 2 V and art. 17 §§2-3). OpenAI's DPA has no ANPD standard
clauses; whether OpenAI would sign them is UNVERIFIED.

## Legal Identity (decision D2)

Heitor decided on 2026-09-29 to open a company (CNPJ) with an accountant and to
name another person as encarregado before launch. Res. CD/ANPD 18/2024 art. 19
§1 II and art. 21 treat the encarregado who also makes the strategic decisions
about the data as a conflict of interest, and Decreto 7.962/2013 art. 2 asks for
a CPF or CNPJ and an address where a product is sold online (how it applies when
Apple sells the subscription is UNVERIFIED).

State today:

- The published identity (since 2026-09-26) is an individual with a CPF who is
  also the encarregado. `web/src/legal.ts` reads it as `isProductionComplete`
  and the pages render it, now labelled "CPF".
- `isLaunchReady` is false, so both legal pages carry
  `data-legal-launch="pending"`.
- The pages take the D2 values without code changes:
  `PUBLIC_NINA_LEGAL_ENTITY_NAME` (company name),
  `PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT` (14 digits reads as a CNPJ),
  `PUBLIC_NINA_LEGAL_ENTITY_ADDRESS`, `PUBLIC_NINA_DPO_NAME` (a name different
  from the company) and `PUBLIC_NINA_DPO_CONTACT_EMAIL`.
- The production preflight fails `deployment.legal-launch-identity` until the
  document has 14 digits, the address is set, and the encarregado is not the
  controller.

## Launch Blockers Before Public Release

Run
`npx deno task preflight:production --env-file config/production.env
--online`
for the same release candidate. The command makes the technical and
legal-metadata items below hard failures where they can be verified
automatically. See `docs/production-launch-runbook.md` for ownership and order.

- D2: company, CNPJ, address and an independent encarregado published on
  `/privacidade` (`data-legal-launch="ready"`).
- Confirm `privacidade@ninai.app` and the report mailbox are monitored, and
  that the 48-hour acknowledgement on `/denuncia/` can be met.
- Confirm the Polícia Federal intake channel for child-safety reports and the
  CVV number (188) shown on `/familias/` before launch; both are UNVERIFIED.
- Confirm the ClassInd symbol colours and artwork against gov.br/mj, and settle
  the App Review questions in `docs/privacy/classificacao-indicativa.md`.
- Create a dedicated Supabase `sb_secret_...` key for the Cloudflare Worker,
  configure `NINA_SUPABASE_SECRET_KEY` and `NINA_WAITLIST_HASH_SALT` as Worker
  secrets, then confirm `/api/health` returns `200`.
- Configure a transactional email provider so every launch email includes the
  fragment-based cancellation link, recipients are selected from current
  `status = 'subscribed'` rows at send time, and provider-side scheduled sends
  honor withdrawals. The waitlist may contain minors; the launch email carries
  no age-specific content.
- Create the Premium subscription group and products in App Store Connect,
  deploy both subscription Edge Functions with App Store verification that
  tries production first and then sandbox (App Review buys in sandbox; never
  Xcode or Local Testing), configure the Server Notifications V2 production URL, and
  confirm Apple's test notification is persisted successfully.
- Apply the transactional account-deletion migration before deploying the
  `delete-account` Edge Function. Keep its Supabase service role key and the
  Sign in with Apple key only in function secrets, alert on stage-only failure
  events, and verify the shared home, solo home, no-house, guardian, invite,
  storage, and Auth deletion fixtures in staging.
- Apply all migrations, require a green database lint/pgTAP CI job, and confirm
  `nina-maintenance` runs daily with failures alerting on non-2xx responses.
- Review App Store privacy labels against the production binary and SDK list.
- Heitor approves the child, health and sensitive-data wording and the legal
  bases; every Law-text-gated string cites its article in
  `docs/privacy/avaliacao-impacto-criancas.md` §9, and Brazilian counsel reviews
  them only if engaged (`docs/production-launch-runbook.md` §7).
