# Record of Processing Operations - Nina

Last updated: 2026-09-29

LGPD art. 37 asks the controller and each processor to keep a record of the
processing operations they carry out, especially those based on legitimate
interest. This is Nina's record, one entry per operation, written from the code
as of the all-ages work of 2026-09-29. It is not legal advice and no lawyer
reviewed it. UNVERIFIED marks a point no primary source confirmed.

Nina processes children's and adolescents' data together with a generative AI
service, which Res. CD/ANPD 2/2022 art. 4 treats as high risk. This record
therefore lists every operation in full instead of leaning on a simplified
small-processor format. The risk assessment for minors is
`docs/privacy/avaliacao-impacto-criancas.md`; the App Store labels are
`docs/privacy/app-store-privacy-labels.md`; the launch checklist is
`docs/privacy/lgpd-launch-posture.md`.

Update this record in the same change as any migration that adds personal data,
any new processor, any change to retention, and the D2 identity change.

## 1. Controller, encarregado and contact

- **Controller and encarregado:** the ones published on
  `https://ninai.app/privacidade/` §1, rendered at build time from
  `PUBLIC_NINA_LEGAL_ENTITY_NAME`, `PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT`,
  `PUBLIC_NINA_LEGAL_ENTITY_ADDRESS`, `PUBLIC_NINA_DPO_NAME` and
  `PUBLIC_NINA_DPO_CONTACT_EMAIL`. The repository is public, so the values live
  only in Cloudflare and `config/production.env`.
- **State today:** an individual with a CPF who is also the encarregado.
- **Decision D2 (2026-09-29):** a company with a CNPJ and an address, and an
  encarregado who is not the controller, before launch (Res. CD/ANPD 18/2024
  art. 19 §1 II and art. 21). `web/src/legal.ts` reports it as `isLaunchReady`;
  the production preflight `deployment.legal-launch-identity` fails until then.
- **Privacy requests:** `privacidade@ninai.app`
  (`PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`), answered within 15 days (art. 19 II).
- **Reports:** `PUBLIC_NINA_REPORT_CONTACT_EMAIL`, the same mailbox until a
  dedicated one exists.
- **Who operates the systems:** only the controller holds production
  credentials today.

## 2. How to read an entry

Each entry lists purpose, data subjects, data, source, legal basis (LGPD
article), whether minors are involved, where it is stored, who can read it,
processors and transfers, retention, and the controls that hold it in place.
"Server" means the Supabase project in `sa-east-1` (São Paulo). Tables in the
`private` schema are reachable by no client role.

## 3. Operations

### R1. Account and sign-in

- **Purpose:** create and keep an account, sign in, authorize every request.
- **Subjects:** every person who signs in, adults and minors.
- **Data:** Supabase Auth user id, the Apple subject identifier Supabase keeps
  for the linked identity, the email Apple shares (possibly a private-relay
  address), display name. An account whose age reads as minor or unknown asks
  Apple for no name or email.
- **Source:** Sign in with Apple.
- **Basis:** contract execution (art. 7 V); for a minor, the guardian's consent
  (art. 14 §1) once a guardian approves them.
- **Stored:** Supabase Auth on the server; the session in the device Keychain.
- **Access:** the person; the server functions.
- **Processors:** Supabase; Apple (identity provider).
- **Retention:** until the account is deleted. Deleting the account also asks
  Apple to revoke the Sign in with Apple token when the app obtained a fresh
  authorization code (R16).
- **Controls:** Sign in with Apple is the only way in (preflight
  `repository.apple-only-sign-in`); the app ships only the publishable key.

### R2. Profile

- **Purpose:** show who is who in the house.
- **Subjects:** account holders.
- **Data:** display name, role, phone, birthday label, availability, preferred
  communication style, a memory note, an avatar, a profile photo. For an
  account whose effective status is minor the server forces email to null and
  every optional field to empty, and no photo can be uploaded.
- **Source:** the person.
- **Basis:** contract execution (art. 7 V).
- **Minors:** name only.
- **Stored:** `profiles` and the private `profile-photos` bucket on the server;
  a protected, backup-excluded copy on the device.
- **Access:** the person; adults of the same house read co-members' profiles.
- **Processors:** Supabase.
- **Retention:** until the person changes it or deletes the account; the photo
  is deleted with the account and when an age signal moves an adult toward
  protection.
- **Controls:** RLS; `profiles_minor_fields_guard`; storage writes only for
  adults.

### R3. Household, membership, invitations and join requests

- **Purpose:** form a house of up to 8 people, invite, approve and remove.
- **Subjects:** adults, minors with an account, children and teens as profiles,
  pets (not personal data).
- **Data:** family name, members (name, relationship, household role,
  permission role, tone, memory note, an adult's optional birth date), invite
  tokens, join requests with a snapshot of the requester's age status and band,
  access decisions.
- **Source:** adults of the house; the requester.
- **Basis:** contract execution (art. 7 V); for minors, the guardian's consent
  (art. 14 §1).
- **Minors:** child and teen rows carry no birth date and no photo; the band is
  never in the member list outside the guardian's supervision block.
- **Stored:** server.
- **Access:** adults of the house; a requester reads their own request and
  decision. Minors read none of it.
- **Processors:** Supabase.
- **Retention:** while the house exists. A minor's or unknown-age person's
  pending request is deleted after 7 days. An access decision stays until the
  person deletes the account.
- **Controls:** clients hold no DML on `families` or `family_members`; every
  change is a SECURITY DEFINER RPC under the family advisory lock; the
  `invite_code` column grant.

### R4. Age assurance and device attestation

- **Purpose:** decide what each account may do, as ECA Digital requires.
- **Subjects:** every account holder.
- **Data:** status (`adult`, `minor`, `unknown`), minor band (`under_12`,
  `12_15`, `16_17`), assurance (`confirmed`, `self_declared`,
  `guardian_declared`, `operator`, `none`), a parental-controls flag, whether a
  household marked the account, when it became a minor, next recheck. App
  Attest key id, public key and counter; single-use challenges stored as
  hashes. Never a birth date, never the range bounds, never a history.
- **Source:** Apple's Declared Age Range on the device, sent through the
  `age-signal` Edge Function, which verifies an App Attest assertion; a
  guardian's declaration at approval; the operator for contests and test
  accounts.
- **Basis:** legal obligation (art. 7 II; Lei 15.211/2025 art. 14).
- **Purpose limit:** feature gating only (Lei 15.211/2025 art. 13; Decreto
  12.880/2026 art. 24; Apple DPLA §3.3.3(O)). Never in AI context, insights,
  logs or anyone else's export.
- **Stored:** `private.account_age_status`, `private.age_signal_challenges`,
  `private.app_attest_keys`; the key id in the device Keychain.
- **Access:** the person reads their own status through
  `get_my_age_status()`, which takes no argument. An approver sees only whether
  a requester is a minor and the band. The operator reads counts through
  `private.age_assurance_distribution()`.
- **Processors:** Supabase; Apple (the signal and App Attest).
- **Retention:** status while the account exists; challenges 1 day; attest keys
  400 days after last use; both deleted with the account.
- **Controls:** `record_age_signal` is service-role only and applies the ratchet
  in SQL; the most protective of the Apple and guardian values wins (Decreto
  12.880 art. 25 §4).

### R5. Minors: profiles, guardianship, consents and acceptances

- **Purpose:** let a parent or legal guardian bring a child or teen into the
  house, and prove the consent given.
- **Subjects:** children and adolescents; their guardians.
- **Data:** declared band, optional nicknames, supervision settings;
  guardianship (relationship, consent text version, guardian assurance, start,
  end and reason); consents per purpose (`account`, `profile`, `health`);
  terms acceptances (who accepted and how); the minor's first-run
  acknowledgement. Guardians are also stored as a salted SHA-256 hash.
- **Source:** the guardian in the app; the minor's own acknowledgement.
- **Basis:** specific, highlighted consent of a parent or legal guardian (art.
  14 §1); keeping the proof: the controller's burden of proof (art. 8 §2) and
  the regular exercise of rights (art. 7 VI).
- **Stored:** `private.minor_profiles`, `private.minor_guardianships`,
  `private.minor_data_consents`, `private.account_terms_acceptances`,
  `private.minor_acknowledgements`.
- **Access:** a live guardian through the supervision block; other adults see
  guardian names and whether consents exist, never the band.
- **Processors:** Supabase.
- **Retention:** settings while the profile or account exists; guardianship and
  consent proof 5 years after it ends, with the user id removed on deletion and
  the hash kept. Profiles created before 2026-09-29 without a guardian are
  deleted after `private.age_policy.legacy_profile_deadline`.
- **Controls:** only an adult whose age Apple confirmed (or the operator) can
  declare; approval writes every row in one transaction.

### R6. Minors: supervision and usage minutes

- **Purpose:** the guardian tools of Lei 15.211/2025 arts. 17-18: alerts, quiet
  hours, a daily limit and 7 days of use.
- **Subjects:** minors with an account; their guardians.
- **Data:** minutes of use per day, supervision settings.
- **Source:** the minor's device measures foreground time; the guardian sets
  the rest.
- **Basis:** guardian consent (art. 14 §1).
- **Stored:** `private.minor_usage_days`; the running counter in protected
  device storage.
- **Access:** live guardians; the minor sees today's minutes and the limit.
- **Processors:** Supabase.
- **Retention:** 30 days.
- **Controls:** `record_minor_usage` accepts only the caller's own day, within
  one day of today in São Paulo, and only ever raises the count.

### R7. Household routine

- **Purpose:** the product: tasks, reminders, seeds, shopping, categories.
- **Subjects:** adults; minors to whom tasks are assigned.
- **Data:** titles, detail lines, due labels and dates, recurrence, owner,
  creator, completion; shopping items; custom categories and sections.
- **Source:** adults of the house; a minor marks their own task done.
- **Basis:** contract execution (art. 7 V). Adults may type health, school or
  document details; for an adult's own health text the basis is the adult's
  own choice to record it (art. 11 I), which nobody has reviewed.
- **Minors:** a minor reads only their own tasks (title, time, glyph) through
  `get_minor_home_view` and writes only done and due through
  `set_minor_task_done`.
- **Stored:** server; a protected snapshot on each adult's device.
- **Access:** adults of the house.
- **Processors:** Supabase.
- **Retention:** while the house exists; completed tasks are archived after 30
  days; an adult's own authored content goes with their account deletion.
- **Controls:** RLS for adults only; realtime silent for minors.

### R8. Health reminders of a minor

- **Purpose:** remember a child's medicine or appointment.
- **Subjects:** children and adolescents.
- **Data:** tasks in category `health` owned by a minor.
- **Basis:** specific consent of the guardian, separate from the others (arts.
  11 I and 14 §1).
- **Stored:** server, in `tasks`.
- **Retention:** as R7. Withdrawing the consent keeps existing tasks and
  refuses new ones.
- **Controls:** trigger `tasks_minor_health_guard`, which also fires when a Nina
  proposal is confirmed.

### R9. Conversation with Nina

- **Purpose:** turn what an adult writes into proposals the adult confirms.
- **Subjects:** adults who consented; people named in what they write.
- **Data:** the adult's AI consent (version, time, transfer consent, withdrawal
  and reason); private chat messages; proposals; memories; per-run metadata
  (model, tokens, cost, latency, status codes, never content); rate-limit and
  budget counters.
- **Source:** the adult.
- **Basis:** consent (art. 7 I), given in the app at the current version.
- **Minors:** never chat. Their names and nicknames are replaced by codes
  before any model call, and their tasks reach no tool.
- **Stored:** server. Chat threads are per adult.
- **Access:** the adult; memories they chose to share are read by the house.
- **Processors:** Supabase; OpenAI (R10).
- **Retention:** messages 30 days, or up to 90 days when reported for review;
  proposals 30 days after resolution (pending ones expire at 30 days); run
  metadata 90 days; memories until deleted; consent rows while the account and
  the house exist, withdrawn rows included.
- **Controls:** `begin_nina_chat_run` requires an adult the server may let use
  the AI, a live consent at the current version with the transfer consent, and
  no AI block; content-free logs; `store: false`; no prompt-cache write.

### R10. International transfer to OpenAI

- **Purpose:** the model call behind R9 and R11.
- **Recipient:** OpenAI OpCo, LLC, United States, as processor. OpenAI does not
  guarantee the country where processing happens.
- **Data:** what the adult writes; the household context the turn needs
  (tasks, shopping, memories, member names), with children, adolescents,
  claimed members of unknown age and non-consenting adults replaced by codes
  and the family name replaced by "Casa". Never minors' tasks, birth dates,
  profile photos, notes about children or age data. Photo and PDF reading stay
  off.
- **Basis:** specific, highlighted consent to the transfer, separate from the
  other purposes (art. 33 VIII), recorded as `transfer_consented_at`.
- **Retention at OpenAI:** no stored responses (`store: false`); abuse-monitoring
  logs up to 30 days, or longer if the law requires. Nina has no Zero Data
  Retention agreement.
- **Published:** privacy policy §6A (Res. CD/ANPD 19/2024 Anexo I art. 2 V and
  art. 17 §§2-3), with a link to OpenAI's sub-processor list.
- **Gaps:** OpenAI's DPA carries no ANPD standard clauses; whether OpenAI would
  sign them is UNVERIFIED.

### R11. Weekly insight

- **Purpose:** a weekly household summary for Premium houses.
- **Subjects:** carriers: claimed adults with a live, current,
  transfer-consented consent.
- **Data:** per-carrier task counts and categories for 7 days; other names in
  free text are replaced by codes.
- **Basis:** consent of each carrier (art. 7 I; art. 33 VIII).
- **Minors:** never carriers, never counted.
- **Stored:** `household_insights` on the server.
- **Processors:** Supabase; OpenAI.
- **Retention:** 90 days.
- **Controls:** no insight with fewer than 2 carriers; the prompt forbids blame,
  intent, mental health and moral value.

### R12. Workload portrait

- **Purpose:** show adults how the open work is spread.
- **Data:** computed on each adult's device from tasks already synced (R7);
  nothing new is stored or sent.
- **Minors:** never drawn and never carriers.

### R13. Premium subscription

- **Purpose:** sell and honor the household subscription.
- **Subjects:** the adult who buys.
- **Data:** original transaction id, product, status, dates, renewal state, the
  signed Apple transaction and renewal info, the app account token (the buyer's
  user id).
- **Source:** the App Store, verified on the server.
- **Basis:** contract execution (art. 7 V).
- **Minors:** cannot buy; a new purchase from an account the server does not
  let buy is refused (`premium_requires_adult`).
- **Stored:** `premium_subscriptions` and its transactions.
- **Processors:** Supabase; Apple sells on its own account.
- **Retention:** kept after account deletion with the user link removed; no
  expiry is implemented. The signed transaction still carries the app account
  token. The retention period is UNREVIEWED.
- **Controls:** Apple JWS verification; the app account token must equal the
  caller.

### R14. Reply reports, AI blocks and child-safety holds

- **Purpose:** handle reports on Nina's replies, suspend the chat of an
  account, and remove and report apparent sexual abuse material (Lei
  15.211/2025 art. 27; Decreto 12.880/2026 art. 39).
- **Subjects:** the reporting adult; the account involved.
- **Data:** report reason code and message reference; block reason code;
  sealed text of a flagged message with its run and family; for an account
  deleted while its hold is preserved, a sealed copy of its Auth user id, Apple
  `sub`, email, creation and last sign-in dates, memberships, chat and memories.
- **Basis:** legal obligation (art. 7 II; Lei 15.211 arts. 27-29); for reply
  reports that concern no child, legitimate interest (art. 7 IX), never for
  health data.
- **Stored:** `private.nina_reply_reports`, `private.nina_ai_blocks`,
  `private.child_safety_holds`, `private.child_safety_preserved_accounts`,
  reachable by no client role.
- **Access:** the operator only, in the SQL editor, following
  `docs/child-safety-runbook.md`.
- **Retention:** reviewed reports 6 months; lifted blocks 1 year; held content
  until the Polícia Federal confirms receipt, then deleted; account data and
  metadata for the period art. 27 §2 requires, implemented as six months after
  receipt (UNVERIFIED until the MJSP act), and dropped at once for a hold
  emptied as a false positive.
- **Gaps:** the Polícia Federal intake channel and the MJSP act are
  UNVERIFIED.

### R15. Report channel and privacy requests by email

- **Purpose:** receive identified reports (Lei 15.211 art. 29 §2 forbids
  anonymous ones) and LGPD requests.
- **Subjects:** whoever writes, with or without an account.
- **Data:** the sender's email and what they write; the request log (date,
  requester, verified account, action, completion date).
- **Basis:** legal obligation (art. 7 II; LGPD arts. 18-19; Lei 15.211 arts.
  28-30).
- **Stored:** the `ninai.app` mailbox. The mailbox provider is not recorded in
  the repository; record it here.
- **Retention:** no period is set yet; the controller sets one here.
- **Controls:** the in-app "Escrever denúncia" attaches no household data; the
  acknowledgement target is 48 hours (the controller's choice; the law sets
  none).

### R16. Export and deletion

- **Purpose:** the rights to access, portability and deletion (art. 18), and
  Apple Guideline 5.1.1(v).
- **Data:** the person's own data, assembled on the server by
  `export_account_data()`; a ward's data by `export_minor_data()` for a live
  guardian. Deletion removes photos, then prepares the database, then deletes
  the Auth user.
- **Basis:** legal obligation (art. 7 II).
- **Stored:** the export is a temporary protected file on the device, removed
  when the screen closes or the app next launches.
- **Apple token revocation:** at deletion the app obtains a fresh Sign in with
  Apple authorization code. After the Auth user is deleted, `delete-account`
  exchanges it for a token and calls Apple's `/auth/revoke`, signing the
  request with a key held only in Edge Function secrets. A failure never undoes
  the deletion and is logged with a stage code only. A guardian's deletion of a
  ward carries no code and revokes nothing.
- **Automatic deletion:** a minor account without a house for 30 days is
  deleted by `nina-maintenance` in the same order.
- **Retention after deletion:** shared household records stay for the other
  members without the link to the deleted account; R5 proof and R13 records as
  stated there.

### R17. Launch waitlist

- **Purpose:** one launch email to people who asked for it.
- **Subjects:** visitors of `ninai.app`, who may include minors.
- **Data:** email, optional first name, consent version and time, locale,
  source, status, delivery records; an abuse fingerprint
  `SHA-256(salt ‖ IP)`, never the raw IP.
- **Basis:** consent (art. 7 I).
- **Stored:** server tables `waitlist_signups`, `waitlist_deliveries`,
  `waitlist_submission_limits`.
- **Processors:** Cloudflare (the Worker); Supabase; Resend (sending, run from
  the operator's machine).
- **Retention:** 24 months from the last submission, or at once on withdrawal;
  fingerprints 1 day.
- **Controls:** unchecked consent box; the unsubscribe token only in the URL
  fragment; answers never reveal whether an address exists.

### R18. Website

- **Purpose:** publish the landing, the Terms, the privacy policy, `/familias/`,
  `/denuncia/` and invite pages.
- **Data:** request metadata handled by Cloudflare; no analytics, no cookies
  for tracking. The invite page reads the code from the URL path.
- **Basis:** legitimate interest (art. 7 IX) for security and delivery.
- **Processors:** Cloudflare.
- **Retention:** Cloudflare's own request logs; their period is UNVERIFIED.

### R19. Operational logs and diagnostics

- **Purpose:** keep the service running and safe.
- **Data:** Edge Function and Worker logs with run ids, model, token counts,
  cost, latency and stable codes only, never message content. Age-signal and
  Apple revocation events carry no user id, age, band, code or token.
  On-device MetricKit reports stay on the device and are never uploaded.
- **Basis:** legitimate interest (art. 7 IX), never for health data.
- **Processors:** Supabase; Cloudflare.
- **Retention:** the platforms' log retention, UNVERIFIED for the current
  Supabase plan.
- **Controls:** source-text tests fail if a log statement references message
  content.

### R20. On the device only

Local notifications (scheduled on the iPhone, no server push, no task detail
line in the body), the protected household snapshot, profile, consent, pending
invite and a minor's usage counter. They never leave the device except through
the synced copies already recorded above.

## 4. Processors and other recipients

| Recipient | Role | What | Where |
| --- | --- | --- | --- |
| Supabase | Processor | Auth, database, storage, Edge Functions (R1-R17) | Project in `sa-east-1`, São Paulo |
| OpenAI OpCo, LLC | Processor | Model calls for the chat and the insight (R9-R11) | United States; processing country not guaranteed |
| Apple | Identity, age signal and attestation provider; seller on its own account | Sign in with Apple, Declared Age Range, App Attest, App Store (R1, R4, R13, R16) | Apple's infrastructure |
| Cloudflare | Processor | Website and Worker (R17-R19) | Global network |
| Resend | Processor | Sending the one launch email (R17) | UNVERIFIED |
| Mailbox provider of `ninai.app` | Processor | Report and privacy mail (R15) | Not recorded yet |

Whether Supabase Inc., Cloudflare and Resend, all United States companies,
create transfers of their own beyond the São Paulo storage is UNVERIFIED. The
OpenAI transfer is the one the privacy policy publishes and the app asks
consent for. Apple's role for Sign in with Apple, Declared Age Range and App
Attest (processor or independent controller) is UNVERIFIED.

## 5. Security measures common to every entry

- Every table has RLS; every privileged operation is a SECURITY DEFINER RPC
  granted to exactly one role; minors hold no table access.
- The app ships only the publishable key; server credentials, the OpenAI key
  and the Sign in with Apple key live only in Edge Function secrets.
- Age data, reports, holds, blocks and guardianship proof live in the `private`
  schema, which no client role reaches.
- Logs are content-free and pinned by source-text tests.
- Sensitive device data sits in protected, backup-excluded files; the App
  Attest key id sits in the Keychain.
- Connections are TLS; the raw client IP never leaves the Worker.
