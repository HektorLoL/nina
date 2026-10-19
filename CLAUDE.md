# Nina — Operating Manual

Last updated: 2026-10-19

This is the working context for anyone (human or agent) making changes in this
repository. It records what Nina is, the rules the code refuses to break, and
the things that will silently go wrong if you don't know them. Read §1 and §2
before touching anything.

---

## 1. Read this first — git history starts at 2026-08-08

Until 2026-08-08 this repo had 3 commits and ~7 weeks of work living only in the
working tree, including all of CI, the preflight tool, 10 migrations, and 3 Swift
sources. That is now committed and merged to `main`.

**This project is trunk-based: everything lands on `main` and gets pushed.**
Commit to `main` and `git push origin main` in the same turn — no feature
branch, no PR, no review flow to wait for. Pushing is what makes CI run, so an
unpushed commit leaves the release gate unverified.

Practical consequences that persist:

- **`git blame` is near-useless before 2026-08-08.** One commit covers seven
  weeks across five workstreams. The commit message enumerates them.
- **CI now runs and is green.** First execution was 2026-08-08 on `main`; all
  four jobs pass, including the full pgTAP suite. Its first run failed 5 of 6
  pgTAP files, which is how the `profiles` grant gap below was found — treat a
  red database job as a real signal, not flakiness.
- **Local secret files are intentionally untracked and have no backup**:
  `Nina/Config/SupabaseSecrets.xcconfig`, `config/production.env`,
  `supabase/.env.local`, `web/.dev.vars`. Each has a tracked `.example` sibling.
  Losing them costs a Supabase dashboard round-trip, not the project.

**Still be careful with destructive git commands** (`git clean -fd`,
`git reset --hard`, `git stash` on a dirty tree). This is a solo repo and
uncommitted work has no remote backup. Committing is still done when the work is
done and asked for, not speculatively — but once committing, it goes to `main`
and gets pushed. Force-push and history rewrites are a different matter: ask.

---

## 2. What Nina is

**A Brazilian-Portuguese iOS app that lets a family dump the mental load of
running a household into a chat with a character named Nina, who turns it into
shared tasks, reminders, groceries, and undated "seeds" — and who quietly
measures who is carrying more of the house.**

- **Who.** Brazilian families, up to 8 people plus pets, iPhone-first. Built for
  the *primary domestic manager* in a two-adult household. Children and pets are
  profiles managed by adults. A person under 18 may hold a guardian-approved
  account that shows only their own tasks; nothing else in the product is
  theirs. Nina has no minimum age; its rating is 14, "Não recomendado para
  menores de 14 anos" (ClassInd's reading of 2026-10-15, accepted by Heitor on
  2026-10-18; it aimed for "Livre" from 2026-09-29 until then, §13).
- **The real problem.** Not task tracking — *the negotiation cost of task
  tracking*. Routing coordination through a neutral third party so assigning
  work stops being an interpersonal act. Secondary: reading Brazilian household
  paperwork (boletos, receitas, comunicados escolares) out of a phone photo.
- **Emotional positioning: relief, not productivity.** The design north star
  file is literally `web/design-references/landing-conversa-alivio.png` —
  *conversation → relief*. Adult surfaces treat her as a friend, not an
  assistant; the login every age sees says only "Nina" and "A rotina da casa,
  dividida." since 2026-09-29, over one button, Apple's own, since 2026-10-04,
  because "Sua amiga Nina" / "Conta pra ela o que
  pesa." invited a child to unload emotionally on a program. The workload
  feature is "Sinal de sobrecarga", subtitled
  *"Um retrato para conversar, não para cobrar"*, never "who is slacking".
- **Market: Brazil, exclusively.** pt-BR hardcoded with no localization catalog,
  prices in reais (`R$ 24,90/mês`), Supabase in `sa-east-1` (São Paulo), LGPD/ANPD
  compliance regime, domain `ninai.app`, bundle `com.heitor.nina`.

### The three product primitives you must not flatten

1. **Nina proposes; humans confirm.** Every AI output is a `nina_proposals` row
   the user accepts. The prompt says it: *"Nunca diga que executou uma ação.
   Toda proposta depende de confirmação humana."* This is not a safety feature
   bolted on — it is the entire trust proposition, and it is a tested invariant
   (`unconfirmed_mutations: 0` in the eval gate).
2. **Sementes (seeds).** An intention you're allowed to have *without* a date.
   `task_kind in ('task','seed')`; renders as "Semente" / "Plante depois". An
   explicit anti-productivity-app stance: most task apps punish undated items;
   Nina names them and lets the AI refuse to invent a date (`due_at: null`).
3. **Nina is a household member who doesn't take a slot.** She is a real
   `family_members` row (`household_role 'assistant'`, `user_id null`,
   relationship `'IA da casa'`). UI copy: her row in Casa reads *"Não ocupa
   vaga."* and the house counts *"2 de 8 pessoas e pets"*.

### Voice

Second-person singular informal (`você`), warm, short sentences, no exclamation
marks, no emoji. Nina is referred to as a person ("a Nina entende"), never as
"the AI" or "the assistant". Read `Nina/MockNinaEngine.swift` before writing any
assistant-facing string — it is the canonical corpus of her voice. The keyword
engine in it compiles into DEBUG builds only (since 2026-10-15); the
`NinaEngineError` lines beside it ship in every build.

**Surfaces a minor can see are the exception** (`MinorViews.swift`, the
login, `AgeCheckView`, the web `/familias/` and `/join/`): Nina is spoken of in
the third person and never says "eu", she is called "um programa de
computador" once per flow (Decreto 12.880 art. 11 I), and she is never
"amiga". The adult chat, nudges and the tutorial keep her person voice.

---

## 3. Architecture map

Four surfaces, one product.

| Surface | Stack | Entry point |
|---|---|---|
| iOS app | SwiftUI, iOS 26.4+, Swift 5 mode, `@Observable` | `Nina/NinaApp.swift` |
| Database | Supabase Postgres, RLS + SECURITY DEFINER RPCs | `supabase/migrations/` (55 files) |
| Server logic | 6 Deno Edge Functions | `supabase/functions/*/index.ts` |
| Web | Astro 7 static + Cloudflare Worker at `ninai.app`, azulejo, light-only | `web/src/worker.ts` |

**Only third-party iOS dependency: `supabase-swift` 2.46.0.** One bundled font
(Fraunces, OFL, subset to 45 KB — the web serves a byte-identical copy) and no
other asset dependency. No analytics SDK,
no crash reporter, no ad SDK — that absence is the mechanical proof behind the
App Store "Data Used to Track You: No" label. Do not add one without revisiting
`docs/privacy/app-store-privacy-labels.md`.

**The trust model in one line:** the iOS app ships only a publishable/anon key,
every table has RLS, and every privileged operation is a SECURITY DEFINER RPC —
so a fully hostile client gains nothing.

---

## 4. Non-negotiable invariants

These are enforced in multiple places on purpose. Breaking one is a security or
product regression, not a refactor.

### Identity & authorization

- **A cached home never grants access.** `activateHomeContext` on remote failure
  sets `.unavailable` and discards the cached `FamilyGroup`. Membership *is* the
  authorization boundary; a cache fallback would let a removed member keep
  reading household data offline. Locked by
  `AppStoreAuthorizationTests.testFailedMembershipVerificationBlocksCachedHomeAccess`.
- **Clients hold no DML on `families` / `family_members`.** The original policy
  allowed `user_id = auth.uid()` in `WITH CHECK`, so any member could PATCH their
  own row to `permission_role='owner'`. Migration `202606100004` revoked the
  table privilege so the policy can never be reached. This is the single most
  important invariant in the schema.
- **Only an `owner` changes permission roles**, and `owner` moves in two ways
  only: the owner offers it and the receiver accepts (since 2026-10-05), or
  `prepare_account_deletion` hands it to the next adult (owner, admin, then
  the oldest member) when the owner's account is deleted. No client RPC grants
  `owner` to the caller. `offer_family_ownership` takes any claimed member the
  list shows as an adult and reads only the caller's own age (through
  `can_manage_family`), never the receiver's; `accept_family_ownership_offer`
  reads only the caller's own (`require_adult_account`, the same bar
  `prepare_account_deletion` sets for a successor), makes the former owner an
  admin and moves `families.created_by`; `cancel_family_ownership_offer` is
  the owner's withdrawal and the receiver's refusal. So neither answer tells
  anyone about another person's age, and an offer makes nobody owner until
  they say yes. One offer per house lives in `private.family_ownership_offers`,
  void after seven days or once its owner no longer holds the house (swept by
  the next offer or withdrawal), and reaches the app as `ownership_offer` in
  the adult home context; offers and withdrawals bump `families.updated_at` so
  realtime carries them. The app offers it as "Passar a casa" in
  the member editor, behind the person's name typed and an ink button, and the
  receiver answers on a card at the top of Casa. An `admin` may not modify
  another owner/admin.
  Nobody removes themselves, the owner, or the assistant row; an adult who is
  not the owner leaves through `leave_family` instead (since 2026-10-05),
  which runs a removal's guardian cleanup and records no access decision, and
  the owner leaves only by handing the house over or by deleting it. The owner's
  title is "Titular" (since 2026-10-05; "Responsável" also named a child's
  guardian), and `create_family` no longer writes the masculine `'Criador'` as
  the creator's relationship.
- **Only the titular deletes a house, and every house is deleted one way**
  (since 2026-10-15, migration `202610150001`, applied to production that day).
  `delete_family(target_family_id, confirmed_family_name)` takes the family
  advisory lock first and refuses anyone but a member whose row says `owner`
  *and* for whom `can_manage_family` holds (`family_delete_denied`, 42501), so
  an admin never deletes over the titular and a titular who became a minor
  keeps the role but not the power. The name must still be the house's
  (`lower(btrim(…))`, `family_delete_name_mismatch`, 22023): the phone folds
  case and accents against the name the person typed and then sends the name
  it shows, so a house renamed meanwhile is never deleted. It and
  `prepare_account_deletion`'s no-successor branches both go through
  `private.delete_household`, which copies every account the house held or
  that wrote in it (a removal or a departure leaves the person's chat and
  memories in the house) into the child-safety preservation table when a hold
  is in its period (a later
  copy merges into it), books
  every open run's reservation as spent (`private.settle_household_ai_runs`;
  a run the cascade took used to strand its reservation and shrink the month's
  cap for good), writes a `'removed'` decision with `house_deleted = true` for
  every other claimed member and a `'declined'` one for every pending
  requester (which is also what starts a minor account's thirty days from the
  deletion rather than from the account's creation), clears every
  `profiles.active_family_id` (a Premium bound to the house then covers none
  and keeps billing), withdraws the house's AI consents with `'house_deleted'`
  (their `family_id` goes null, the rows stay), and deletes `families`; the
  cascade takes the rest, every adult's private memories included, and
  the `BEFORE DELETE` trigger on `family_members` closes a minor's links and
  consents, kept as proof. `get_family_access_decision` returns
  `house_deleted`; a build up to 14 ignores it and reads a plain removal,
  never a refused request. Other phones learn it on their next verified load
  (a return to the app, a pull, a failed write): a realtime delete carries no
  filterable row. The decision screen says it alone: a refresh that lands on a
  decision adds no red "Você não faz mais parte desta casa." unless edits were
  discarded. The app offers "Apagar a casa" to the titular alone, in Ajustes
  › Casa and from the titular's "Sair da casa", behind the house's name typed,
  an ink button and a confirm alert, with the "Sua assinatura continua." card
  for a subscriber. A deletion whose answer was lost reads `family_not_found`
  on the retry, which the phone takes as done ("Casa apagada."), and any other
  next read of the house (a pull, a return to the app, the realtime rejoin)
  that finds it gone with no decision lands there too, never on the red
  removal line
  (`AppStoreAuthorizationTests.testADeletionWhoseAnswerWasLostReadsAsDeletedWhenAPullFindsTheHouseGone`);
  the lost attempt itself reads "A resposta não chegou. Tente de novo."
  (`RemoteWriteAnswer.mayHaveBeenLost`: a `URLError` or a gateway 5xx), and
  "Não deu para apagar a casa agora." only follows an answer that arrived or a
  request never sent. The phone says "Casa apagada." only when that reload
  lands on no house and no decision: the server records none for the titular
  who deletes, so a titular removed meanwhile (after handing the house over)
  lands on the removal and never reads that a house which still stands was
  deleted (`AppStoreAuthorizationTests.testATitularRemovedWithoutKnowingItIsNeverToldTheirHouseWasDeleted`).
  A reply another adult reported and is still held for
  review survives the deletion as a copy on its report (§4 AI, the child-safety
  hold). On every other path `family_not_found` reads "Você não faz mais parte
  desta casa.", because the server raises it for a removal as well as a
  deletion.
- **A claimed member's `household_role` is derived from age, never chosen by a
  client** (since 2026-09-29; it used to be forced to `'adult'`). The trigger
  `family_members_enforce_age` sets it from `private.effective_age`: adult →
  `'adult'`, under 12 → `'child'`, 12–17 → `'teen'`, and a claimed minor needs a
  live guardianship. `update_family_member` can never set a claimed row's role,
  so an admin still cannot demote a real person and strip what they may do.
  What a claimed member *may do* comes from age status, not from this column
  ("Age and minors" below).
- **`invite_code` is enforced by a column grant, not by masking.** `authenticated`
  holds `select` on every `families` column *except* `invite_code`; the masking
  inside `get_current_home_context` is the second layer, not the first. Until
  2026-08-09 only the masking existed, so any member could read the code straight
  off the table via PostgREST and hand out household access. This is also what
  makes `families` safe to publish to realtime — `replica identity full` puts
  every column in the WAL row, and the per-subscriber filter drops `invite_code`
  only because the grant is absent. Never widen that grant back to the table.
- **Possessing an invite link grants nothing.** `request_family_join` creates a
  *pending* request; an owner/admin approves. Both the app and the public web
  invite page state this. Invite tokens are `casa-` + 128 bits of
  `gen_random_bytes(16)`, one active invite per family, 7-day expiry, ≤7 uses.
- **Sign in with Apple is the only way in (decided 2026-09-26).** No email
  code, no magic link, no Google, no password: `AuthClient` has one sign-in
  method, `signInWithApple`, and the welcome shows one door over the legal
  line and the rating mark: the black system "Continuar com a Apple", whose
  request carries `requestedScopes = [.fullName]` for every account (decided
  2026-10-05, build 12; build 11 asked for no scope), so Apple may share a name
  and is never asked for an email; the age step runs after sign-in. App Review
  Guideline 4.0 refuses an app that asks for a name after Sign in with Apple
  when Apple could have shared it, which is why the scope is back, for every
  age alike. Of the name only `PersonNameComponents.givenName`, trimmed, is
  kept (`ProfileNaming.givenName`; never the family name, a middle name or a
  nickname): `AppleSignInCredential` has no other name field. The sign-in
  sends no name at all: `ensure_current_profile` still gets a null
  `display_name_hint`, nothing writes any part of the name to Auth user
  metadata or a log, and the given name reaches the server only as a name the
  person is saved with (next bullet). Apple sends the name only on an
  account's first authorization, and the person may blank it in Apple's sheet. An
  account made since build 11 has no email. An earlier account keeps the one
  Apple shared then (a private relay address when the person hid theirs), shown
  read-only in Ajustes and the profile only when present (`AuthUser.shownEmail`);
  nothing links or changes a sign-in email. An identity token without the email
  scope carries no email claim, so production Auth must keep Apple's "Allow
  users without an email" (`email_optional`) on or GoTrue refuses every new
  account; `/auth/v1/settings` does not report it, so it is a runbook §2 step,
  not a preflight check (`supabase/config.toml` sets it for the local stack).
  The only other door, `DebugAuthAccount` (teste1/teste2@ninai.test, local
  home, no backend), exists only under `#if DEBUG`, and `artifact.debug-sign-in`
  fails the release preflight if its addresses reach the bundle. Production Auth must
  answer `/auth/v1/settings` with Apple on and Email, Google, passkeys and every
  other provider off; `deployment.sign-in-providers` fails the online preflight
  otherwise. On the client, `repository.apple-only-sign-in` fails the repository
  preflight if any tracked `Nina/` Swift source calls an OTP, magic-link, password,
  OAuth or non-Apple ID-token sign-in or changes a sign-in email (pinned by
  `"the shipped app signs in with Apple and calls no other sign-in door"`),
  `repository.apple-sign-in-scopes` fails it if any of them assigns a scope
  list other than `[]` (the deletion reauthorization asks for none) or
  `[.fullName]`, adds to one, or names the email scope, or unless every scope
  list `LoginView.swift` assigns is exactly `[.fullName]` (pinned by `"the
  shipped app asks Apple for the name alone and never the email"`; `"Apple's
  given name reaches neither Auth nor the profile at sign-in"` pins the null
  hint); `AuthSessionTests.testTheSignInAsksAppleForTheNameAloneAndNeverTheEmail`
  reads the configured requests, and
  `AuthSessionTests.testNoSignInLineNamesAnotherDoor` keeps every sign-in error
  line from naming an email, a code or Google.
- **A house member is named by the person, never by the server's placeholder.**
  `create_family` and `request_family_join` copy the profile name into the
  frozen `family_members.name`, the approver's card and the model roster
  (where `'Família'` would alias the common word "família"). Every account made
  since build 11 reaches its profile as `auth_user_display_name`'s `'Família'`,
  and a name the sign-in passed as an auth-owned hint would not survive anyway:
  `get_current_home_context` runs `ensure_current_profile(null)` on each load
  and re-derives every `display_name_source = 'auth'` row. So the sign-in
  sends no hint, and nothing about the person reaches the server before the
  age is known. Apple's given name waits on the phone instead
  (`AuthSessionStore.sharedGivenName`, a `SharedAppleName` in
  `ProtectedLocalDataStore` under `PrivateLocalDataScope.sharedAppleName`).
  It is held before the token exchange, keyed by Apple's user id, so a sign-in
  that fails after Apple's sheet keeps it for the retry or the restored
  session (Apple shares the name only once); it binds to the account that
  signs in with that Apple ID only while the server's answer is a placeholder
  (a name the person chose earlier outranks it), survives a relaunch, and is
  removed when the person is named, on sign-out and on deletion. The Apple ID
  match is the guard: one Apple ID's name never names another account.
  `HomeSetupView` and `InviteAcceptanceView` save it through
  `ProfileStore.chooseDisplayName` (a narrow `profiles` update of
  `display_name` and `display_name_source = 'user'`) before the RPC, with no
  field on screen (`ProfileNaming.nameToSave`), and never over a different name
  the person chose in Perfil since; the tutorial greets the person by it. "Seu
  primeiro nome" shows only as the fallback when Apple gave no given name and
  `ProfileNaming.needsName` reads `'Família'`, `'Você'` or an empty name
  (`ProfileNaming.asksForName`). The phone counts a name as chosen only after
  the server holds it. A minor, or anyone whose age Apple has not shared, still
  confirms a first name beside the invite (`MinorNoHomeView`, server
  `needs_name`), and Apple's given name only fills that field; when that screen
  appears the phone drops its stored copy (`keepSharedGivenNameOffDevice`), so a
  minor's given name reaches the server only as the name they confirm and
  stays on the device only in memory. An unknown-age adult who relaunches
  before sharing the age therefore types the name at house setup.
  `ChosenNameField` lives only on adult screens. Locked by
  `AuthSessionTests.testOnlyTheGivenNameAppleSharesIsKeptAndItIsTheOnlyNameTheServerReceives`,
  `…testABlankOrMissingAppleNameLeavesTheTypedField`,
  `…testAnAdultWhoSharedTheirNameIsNeverAskedAndItIsSavedBeforeTheHouseCopiesIt`,
  `…testApplesSharedNameSurvivesARelaunchUntilThePersonIsNamed`,
  `…testAFailedSignInKeepsApplesNameForTheRetryOfTheSameAppleIDOnly`,
  `…testAMinorsFieldIsFilledFromApplesNameButNoCopyOfItStaysOnTheDevice`,
  `…testANameThePersonAlreadyChoseOutranksTheOneAppleSharesAgain`,
  `…testANameChosenInPerfilAfterApplesIsNeverOverwrittenWhenTheHouseIsSetUp`,
  `…testAChosenNameCountsOnlyOnceTheServerHoldsIt`,
  `…testANewAppleAccountIsAskedForItsNameAndANamedOrDebugAccountIsNot`, the
  pgTAP "a house created after the person chose a name names its owner with it"
  and the Deno "the app reads the server's fallback name as no name".
- **8 non-assistant people per home**, enforced in three places (trigger,
  `request_family_join` count, remaining-slot arithmetic) under a family
  advisory lock taken *before* any row lock.

### Age and minors

Built 2026-09-29 from the all-ages spec (Heitor's decisions D1–D4: aim for
"Livre" and keep the chat if the rating comes back 10 or 12, which ended on
2026-10-18 when Heitor accepted ClassInd's 14 with the chat and Premium
unchanged, §13; a company and an
independent encarregado before launch; only Apple-confirmed adults act for
minors, and D3, decided again on 2026-10-14, lets self-declared adults also
chat and buy Premium; iOS 26.4 everywhere). The research and the capability
table are in `docs/privacy/avaliacao-impacto-criancas.md`.

- **Age is a server-held band written only by `record_age_signal`.** It is
  executable by `service_role` alone and reached only through the `age-signal`
  Edge Function, which verifies an App Attest assertion over a single-use
  challenge and the canonical 7-key signal JSON. The ratchet lives in that SQL,
  so a compromised function still cannot move an account toward less
  protection: adult → minor, a younger band or adult → unknown apply at once
  (live AI consents withdrawn with `age_status`, admin dropped, role re-derived,
  pending proposals rejected, profile photo and optional fields cleared);
  minor → adult needs an Apple `confirmed` signal or the operator
  (`age_signal_rejected` otherwise); unknown → adult only when no minor record
  ever existed. A declined share is not a minor record: `minor_since` is stamped
  only for a minor status, so an adult who once declined Apple's sheet may
  self-declare again, while a former minor or a household-marked account still
  needs `confirmed` (pgTAP "an adult who once declined may self-declare
  again…"). An operator's mark outlives the phone (migration `202610140001`):
  an adult signal over an `operator` adult, self-declared or confirmed, keeps
  the assurance `operator` and reports no change, parental controls still
  follow the device, and a minor or declined signal replaces the mark at once
  (pgTAP "an operator-marked adult keeps the mark and the trust after a
  self-declared adult signal", "parental controls follow the device under the
  mark and leave the account trusted for nothing", "a minor signal drops the
  operator's mark"); the app reads a retry over a mark left in place as "A
  Apple manteve a mesma resposta."
  (`AgeAssuranceTests.testARetryTheServerAnswersWithTheOperatorsMarkLeftInPlaceSaysAppleKeptTheSameAnswer`).
  Before it, any signal replaced the mark. Nina never stores a birth date, the
  range bounds or a history of ranges. The band never enters member lists,
  model context, logs, the insight or anyone else's export, and **no function
  a client may execute answers about a user other than the caller**:
  `get_my_age_status()` answers
  about the caller only, and must never gain a parameter or it becomes an age
  oracle. `can_manage_family` reads age status and takes a user id, so since
  migration `202609290009` no API role executes it, nor `is_family_member` or
  `is_family_creator`, whose subject is also an argument; SECURITY DEFINER RPCs
  call all three as their owner. `shares_family_with`, which the profiles
  policy evaluates as the signed-in role, keeps its grant and answers only when
  its subject is the caller (pgTAP "no API role executes a predicate that
  answers about the user it is handed", "shares_family_with never links two
  people other than the caller").
- **Unknown is the most protective state, on both sides.** An account with no
  age row is treated as the youngest band (Decreto 12.880 art. 25 §4): it
  cannot create a house and can only enter as a minor a guardian approves
  (then `household_marked`). The app decodes a missing or unknown
  `household_role` as `.unrecognized`, never `.adult`, and a home context
  without `viewer_kind` as a minor's
  (`RemoteDecodingTests.testAnUnknownOrMissingHouseholdRoleNeverReadsAsAnAdult`).
- **Capabilities come from `AgeStatus`, never from `household_role`.** Three
  levels: *trusted adult* (status adult, no active parental controls, assurance
  `confirmed` or `operator`) may act for a minor; `may_use_ai` and
  `may_buy_premium` follow `private.age_policy.trusted_assurances` instead, the
  D3 switch. A migration creates it as `{confirmed,operator}`; decision D3
  (Heitor, 2026-10-14) adds `self_declared` to production's row with one
  operator statement, not a migration, and §13 records when it ran (Apple does
  not confirm adult ages in Brazil; the reasoning is in
  `docs/privacy/lgpd-launch-posture.md`, "Decision D3"). Acting for a minor is
  hard-coded to the two proven assurances in `private.is_trusted_adult` and
  never widens with the policy row, and active parental controls still mean
  not trusted for anything. So, with `self_declared` in the row, a *declared
  adult* runs a house, chats once they accept the notice and buys Premium, but
  never approves a minor, adds a child or answers for one. An adult whose
  `may_use_ai` is false meets a gate where the chat would be: with parental
  controls on, "A conversa não abre nesta conta." and "O Premium não abre
  nesta conta." (the tour's closed line), which never name Apple's
  confirmation (`AppStore.chatWaitsForConfirmedAge`,
  `…testParentalControlsCloseTheChatWithoutSayingItWaitsForApplesConfirmation`);
  otherwise, a self-declared adult while the row leaves `self_declared` out,
  "A conversa pede idade confirmada." (and the tour's "quando a Apple confirmar
  sua idade"). A *minor* or *unknown* account never mounts the four tabs.
- **Minors hold no table access.** Every household policy uses
  `is_adult_family_member` (migration `…0003`); a minor reads only through
  `get_minor_home_view` (their own tasks: title, time, glyph, done — never
  `subtitle`, never anyone else's work) and writes only through
  `set_minor_task_done`, `record_minor_usage` and `acknowledge_minor_terms`.
  `get_current_home_context` returns a minimized shape with `viewer_kind:
  'minor'` to any non-adult, so an old build can show a minor nothing. Realtime
  follows RLS, so a minor's device gets no row events by design; it refreshes on
  foreground, after its own writes and on pull.
- **A minor enters only through one atomic guardian approval.** A trusted owner
  or admin calls `approve_family_join_request` with the declaration
  (`guardian_declared`, relationship mãe/pai/responsável legal), a band no
  older than Apple's, and the current `consent_version`; the member row, its
  `minor_profiles`, the guardianship, the `account` consent (and an optional,
  separate `health` consent) and the Terms acceptance are written together or
  not at all. The same rule covers `add_minor_profile` for an account-less child
  or teen. Minors are always `permission_role = 'member'`
  (`minor_role_restricted`), never have a `birth_date` or photo, and a health
  task for a minor without a live health consent raises
  `minor_health_consent_required`, including through `resolve_nina_proposal`.
  `can_manage_family` is the single choke point for house powers and is false
  for anyone who is not an adult today, owner included.
- **A guardianship never outlives the guardian's place in the ward's house.**
  `private.is_live_guardian` requires a live link *and* an adult membership in
  the ward's house, so export, supervision, removal and guardian deletion all
  fail for someone who left. `remove_family_member` ends a removed adult's links
  there (`guardian_left`) and withdraws the consents they gave; account
  deletion withdraws every consent by the deleting guardian's hash; a `BEFORE
  DELETE` trigger on `family_members` closes a child's or teen's links and
  consents however the row goes, a house deletion's cascade included, so no
  proof stays open for a profile that no longer exists. Withdrawing a minor's
  health consent deletes that minor's health reminders (their titles alone
  reveal health), behind a confirm alert.
- **Kids mode is presentation only.** `KidsMode.isOn` turns on for the
  `under_12` band or an explicit "Modo criança" switch in a minor's Ajustes
  (stored as a UI preference, `nina.kidsMode.override`). It reads the same
  `get_minor_home_view` rows and writes through the same
  `set_minor_task_done`; it adds no field, no request and no capability, and
  its strings follow the minor voice (no "eu", no emoji). It is the one
  surface where category gets a colour (`NinaTheme.Kids`).
- **Guardians supervise; nothing pushes toward weaker settings.** Quiet hours
  are forced on for a minor's device (21:00–07:00 by default), there are no
  follow-up nudges, the notification body is the neutral "{título} · {hora}",
  and the daily limit starts at 30 minutes. The usage ledger lives in
  `ProtectedLocalDataStore`, never `UserDefaults`, and syncs through
  `record_minor_usage` (monotonic per day). Only a live guardian prints or
  shares a child's day; any adult may still "Mostrar" an account-less child's
  list (`ChildDayTests.testOnlyALiveGuardianCanPrintOrShareAChildsDay`).
- **No minor's identity or tasks reach OpenAI.** Every model-bound string —
  the new message, recent turns, memories, member context, tool results, the
  moderation input, the `/v1/responses/input_tokens` pre-count and the main call
  — passes `Pseudonymizer` (`_shared/nina-pseudonyms.ts`): children become
  "Criança N", teens "Adolescente N", unknown claimed accounts "Pessoa N", an
  adult other than the requester without a live consent "Adulto N", the family
  name "Casa". Matching is whole-word, case- and accent-folded, and covers
  registered nicknames and every name a member is known by (the roster's
  `names`: profile name and the name the house registered, which a later
  rename does not update). In free text a name a minor shares with an adult is
  aliased as the minor; the adult gets an "Adulto N" code of their own, even
  with a live consent, so structured fields name them without the shared word:
  workload buckets, owner labels in tool results, member context and the
  requester's `current_user` are named from the member id
  (`Pseudonymizer.structuredName`), and the weekly metric keys through
  `structuredKeys`. A minor code that entered a turn only through a first name
  an adult also carries goes back as the word the person typed and never owns a
  proposal (`restoreProposals` sets the owner to "Casa"); a minor named in full
  or by nickname restores to the minor. `restoreText` / `restoreProposals` map
  aliases back before anything is stored. Tasks owned
  by a child or teen are left out of every tool data source and the insight. An
  unregistered nickname passes — a stated limitation, not a bug.
- **Children and adolescents are never drawn in the portrait or the insight.**
  `HouseholdWorkload` counts adults alone (`HouseholdRole.isWorkloadCarrier`):
  `.child`, `.teen`, `.unrecognized` and, since 2026-10-15, `.pet` carriers are
  left out at the `isConclusive` gate and in the entries, and Casa's dormant
  "Aparece quando outro adulto entrar na casa." shows while the house has one
  adult, however many children or pets live there (`waitsForAnotherAdult`), and
  presumes no partner. The weekly insight counts only claimed adults with a
  live, current consent and skips a house with fewer than 2 of them, so a
  covered house's "Resumo semanal" row on Casa reads "Chega quando 2 adultos
  aceitarem conversar com a Nina." and the paywall's note "Quando 2 adultos
  aceitarem conversar com a Nina.": a condition, never a statement that it is
  already met.

### AI

- **Nina never mutates household data.** Four read-only tools; every durable
  change is a proposal resolved by `resolve_nina_proposal`.
- **A turn Nina never answered shows no reply, and no shipped build answers in
  her name from the phone** (since 2026-10-15). Until then a Release build
  answered a failed turn with `MockNinaEngine`, the keyword engine, which skips
  moderation, the CVV line and the medical refusal. `MockNinaEngine`,
  `AppStore.fallbackNinaEngine` and the demo house (`DemoHouse`) now compile
  into DEBUG builds only, and a Release build with no Supabase client gets
  `UnavailableNinaEngine`. On `.offline`, `.unavailable` or any error that is
  not a server refusal, `sendMessage` takes the person's message out of the
  thread, puts its words and attachments back in the composer
  (`restorableDraft`, `restorableAttachments`, memory only) and shows one
  `NinaErrorNote` (`ninaSendFailure`): "Sem conexão. Tente de novo." only when
  the request found no network (`NinaEngineError(transportError:)`), otherwise
  "Não deu para a Nina responder agora. Tente de novo.", because a drop or a
  timeout may have reached the server. Words typed while Nina was reading stay
  after the restored ones, never in place of them
  (`NinaChatView.restoredComposerText`, locked by
  `…testWordsTypedWhileNinaWasReadingStayAfterTheRestoredOnesAndNeverReplaceThem`).
  A failure whose outcome is unknown (`NinaEngineError.unconfirmed`: a timeout, a
  dropped connection, a gateway answer with no code) keeps its message id in
  memory (`unconfirmedTurn`), so the same words sent again replay that turn
  through `begin_nina_chat_run`'s idempotency instead of running and charging it
  twice, with no second bubble when a refresh already shows the server's copy of
  the line; a failure the function reported with its own code gets a new id,
  because a failed run answers its old id with `request_in_progress` forever. A
  replay that meets `request_in_progress` keeps the id and shows "A Nina ainda
  está lendo essa mensagem. Espere um instante." as the error note, never as
  Nina's line, but only while the first run could still answer
  (`AppStore.lostTurnMayStillBeRunning`: 240 s after the uncertain attempt,
  longer than nina-chat's own timeouts let any run last, about 195 s with every
  tool round); after that the next send is a new turn. The window reads
  `AppStore.now`, the store's injectable clock, which also stamps the person's
  line (locked by
  `…testALostTurnStillInProgressPastItsLastPossibleAnswerIsLetGoAndTheNextSendIsANewTurn`).
  When a refresh brings the lost id followed by a Nina line, the turn is
  settled: the error note goes, an unconsumed restore is dropped, and
  `answeredDraft` lets the composer let go of the same words and attachments if
  the person has not changed them (`NinaChatView.composerAfterAnsweredTurn`:
  the trimmed words must match, and only the turn's own attachments go), so an
  answered turn is never sent twice (locked by
  `…testResendingATurnWhoseAnswerWasLostReplaysItsIDSoTheServerNeverRunsItTwice`,
  `…testATurnTheServerSaidFailedOrNewWordsAreSentAsANewTurn`,
  `…testALostTurnWhoseAnswerArrivesLaterClearsItsErrorAndIsNeverSentTwice` and
  `…testTheComposerLetsGoOfASettledLostTurnOnlyWhileItStillHoldsTheSameWords`).
  No refusal adds a line in Nina's name, because the server stores no reply to
  a refused turn and a line held only on the phone would vanish at the next
  refresh (`apply(_:)` replaces the thread). Refused content
  (`input_not_supported`) leaves only the person's line as the "Mensagem não
  enviada." the server keeps, never the words or attachments back in the
  composer, and the error note "A Nina não pode ajudar com esse conteúdo. Se
  houver risco imediato para alguém, procure uma pessoa de confiança ou o
  serviço de emergência.", which carries the safety pointer the server's own
  refusal does; since moderation runs after `begin_nina_chat_run` passed every
  ceiling, it also ends any refusal held in `AppStore.chatRefusal`. Every other
  refusal is raised by `begin_nina_chat_run` (or the adult check before it)
  before it stores anything: the person's line is withdrawn, the words and
  attachments go back to the composer, and the store fires the error haptic.
  The message limit, the shared budget, Premium-only attachments and the adult
  check are held in `AppStore.chatRefusal` until the next answered turn, so no
  refresh erases what the composer says (`ChatComposerNotice.refusal`): a
  quota refusal reads "Limite de mensagens. No Premium, 50 por dia." with
  "Ver o Premium" for an account that may buy in a house that is not covered,
  otherwise "Limite de mensagens. Anote pelo + em Hoje."; attachments read "Ler
  foto e documento é do Premium." with the same route, or "Foto e documento são
  do Premium." without it; the budget reads "Conversa pausada. Anote pelo + em
  Hoje." (`AppStore.isChatPausedForBudget`) with no Premium route, since no
  purchase lifts a shared pause. A limit or attachment refusal ends when the
  house becomes covered. An adult refusal closes the chat to the adult gate
  (`canUseNinaAI`) until the house is read again. A missing consent
  (`ai_consent_required`, withdrawn on another phone) brings back the consent
  card, like an outdated one but without "Este aviso mudou.", and a message
  too large shows "Essa mensagem ou anexo é grande demais para a Nina." as the
  error note (locked by
  `…testARefusalTheServerKeptNothingOfLeavesNoLineInNinasNameAndPutsTheWordsAndAttachmentsBack`,
  `…testARateLimitKeepsTheWordsAndThePremiumRouteThroughARefresh`,
  `…testABudgetPauseKeepsTheWordsAndThePauseThroughARefreshUntilATurnIsAnswered`,
  `…testAnAdultRefusalShowsTheAdultGateUntilTheHouseIsReadAgain`,
  `…testOnlyAPersonWhoMayBuyForAnUncoveredHouseIsOfferedPremiumForARefusal`
  and `…testRefusedContentAddsNoLineInNinasNameAndEndsTheCeilingItGotPast`).
  `repository.debug-only-mock` fails the repository preflight if any of the
  three names appears outside an `#if DEBUG` branch of a tracked `Nina/`
  source, and `artifact.debug-chat-engine` fails the archive gate if the binary
  carries the mock's replies or the demo house. Locked by
  `AppStoreAuthorizationTests.testATurnNinaNeverAnsweredLeavesNoReplyAndPutsTheWordsBackInTheComposer`,
  `…testOnlyARequestThatFoundNoNetworkIsToldThereIsNoConnection` and
  `…testAShippedBuildWithNoServerNeverAnswersInNinasName`.
- **Confirming a corrected proposal must bind the correction.** Editing a
  proposal's fields before accepting goes through `NinaProposalPayload.edited(…)`,
  which recomputes `dueAt` from the edited `dueLabel` whenever the label changed
  and sets it to `nil` when `inferredDueAt` cannot parse the result. A corrected
  reading that produced an uncorrected `due_at` would make the confirmation
  ritual — the product's whole trust proposition — decorative. Locked by
  `RemoteDecodingTests.testCorrectingWhenAProposalHappensMovesTheScheduledDateAndNotJustTheLabel`
  and `…testAnUnparseableCorrectionLandsUndatedRatherThanKeepingTheModelsDate`.
  Since 2026-09-26 it also holds on the wire: `NinaProposalPayload.encode(to:)`
  always writes `due_at`, as JSON `null` when there is no date. Until then the
  synthesized encoder dropped the key, and `resolve_nina_proposal` merges the
  edited payload over the stored one with `||`, so Nina's stored date survived an
  undated confirmation and the "lands undated" rule held only in memory.
- **A named day is never confirmed undated.** Proven in production on
  2026-09-26: "Me lembre de pagar o boleto dia 20" became a reminder labelled
  "Dia 20" with `due_at` null, so no notification could ever fire. Three layers
  now read days by one rule (§12, "`dueLabel` and `dueAt` are read by one rule"):
  (1) the prompt tells Nina to compute `due_at` from `local_now` (São Paulo date,
  weekday, time and offset, built by `ninaLocalNow`) whenever the person or an
  attachment names a day or time; (2) `fillMissingDueAt` in
  `_shared/nina-due-date.ts` dates a task or reminder the model left undated from
  its label, or from the message when it is the only dated proposal, before
  `complete_nina_chat_run` stores it; (3) the app's accept path
  (`NinaProposal.confirmationPayload` → `datedFromLabelIfUndated`) dates an
  untouched task or reminder label, so the card shows the day before the tap and
  proposals left pending from before the deploy get one too. None of the three
  gives a seed, a purchase or a memory a date, or moves a date Nina gave. The
  server only re-spells hers as São Paulo time with seconds and offset, reading
  one written without a zone as São Paulo wall time (Postgres would read it as
  UTC, three hours early); a `due_at` naming a day that does not exist, or no
  instant at all, is re-read from the label or the message, or dropped to null.
  The phone reads Nina's date with or without seconds and re-reads the label
  only when `due_at` is missing or unreadable.
  Locked by
  `AppStoreAuthorizationTests.testConfirmingAnUndatedReminderWhoseLabelNamesADayBooksThatDay`,
  `RemoteDecodingTests.testAnUndatedConfirmationSendsAnExplicitNullSoNinasStoredDateCannotSurviveIt`,
  `…testANinaDateWrittenWithoutSecondsIsReadAndConfirmedExactlyAsSheWroteIt`
  and the Deno test "a due_at without a zone keeps Nina's São Paulo hour, and
  an unreadable one is re-read from its label or dropped".
- **Adults the age policy admits only**, checked in the Edge Function (member
  row with `household_role 'adult'`) *and* again inside `begin_nina_chat_run`,
  which refuses in order: not an adult member (`nina_adult_access_required`),
  `may_use_ai` false (`age_confirmation_required`, surfaced as
  `nina_age_confirmation_required`; since D3 a self-declared adult passes, and
  the code keeps its name), blocked (`nina_ai_blocked`), no consent,
  outdated consent (`nina_consent_outdated`), no transfer consent
  (`nina_transfer_consent_required`). Each code is matched whole on both sides.
- **AI consent is a server-side record, not a device flag.** `nina_ai_consents`
  holds one live grant per adult per home and keeps withdrawn rows — LGPD expects
  demonstrable consent, and a reinstall must not read as "never accepted".
  Deleting a house withdraws its grants (`revoke_reason 'house_deleted'`) and
  its foreign key sets `family_id` null instead of cascading (migration
  `202610150001`), so a titular's deletion never erases another adult's grant
  or transfer consent.
  `begin_nina_chat_run` and `get_nina_weekly_candidates` both require a live
  grant, so revoking on one phone actually stops the other adult's chat and stops
  the Sunday insight from shipping member display names to OpenAI. On the phone
  a grant opens the chat only once `record_nina_ai_consent` has answered (since
  2026-10-15): the card stays up with "Aceitar e conversar com a Nina" pending,
  and a failed save leaves the transfer box ticked with the error above the
  button; a withdrawal still stops the chat at once. Only a build with no
  backend, or a DEBUG account, mirrors a grant before any server. Locked by
  `AppStoreAuthorizationTests.testAGrantOpensTheConversationOnlyOnceTheServerHasRecordedIt`.
- **A consent counts only at the current version and with its separate
  transfer consent.** Consent v2 (2026-09-29) names OpenAI, says the text and the
  house details it needs go to the United States, that OpenAI may keep abuse
  logs up to 30 days, and asks for the international transfer in its own
  unchecked box (LGPD art. 33 VIII); "Aceitar e conversar com a Nina" stays
  disabled until it is ticked. Migration `…0006` withdrew every earlier grant
  with reason `policy_changed`, because it was given on text that said nothing
  was kept (LGPD art. 9 §1): every adult, TestFlight testers included, sees
  "Este aviso mudou." and accepts again. `PrivacyPolicyVersion.current` in
  `AppStore.swift` and `private.age_policy.current_policy_version` move
  together; the app treats an older version as no consent
  (`AppStoreAuthorizationTests.testAnOlderConsentVersionCountsAsNoConsent`).
- **No string may claim that nothing sent to the model is kept.** "fica
  guardado lá", "servidor nenhum", "usado só para responder" and "não guarde o
  que recebe" fail `repository.retention-claims` and the Deno test "no Swift or
  web string claims nothing is kept at the model provider".
- **The model's own words are moderated too.** After `restoreDeep`,
  `moderateOutput` runs `omni-moderation-latest` on the reply and the proposal
  text before `complete_nina_chat_run`; a flag replaces the reply with "Não
  consigo ajudar com isso aqui.", drops the proposals and logs
  `nina_output_moderated` with no content. A request for diagnosis, symptoms,
  medication choice or dose is answered before any model call by
  `asksForMedicalGuidance` ("Isso é com um profissional de saúde. Posso lembrar
  você de ligar ou marcar a consulta."); a reminder is not a request, but a
  change of dose is refused even when it mentions a reminder ("Acho a dose alta.
  Reduza pela metade e atualize os lembretes." never reaches the model). The
  prompt forbids sexual, violent, discriminatory, profane and drug content,
  offering a romantic or sensual version of it, and medical or emotional
  guidance, and tells Nina the aliases are people of the house — each line
  pinned by a source-text test.
- **Someone who writes about hurting themselves always meets the CVV line.**
  When input moderation flags a `self-harm*` category (and not `sexual/minors`),
  `nina-chat` skips the model and completes the turn with `ninaSupportReply`
  ("…ligue 188, o CVV, de graça, a qualquer hora…"), a normal 200 answer every
  build shows. Any other flagged message gets `400 input_not_supported`, and
  `redact_refused_nina_message` (service_role only) leaves only "Mensagem não
  enviada." on the server, so a refresh cannot bring the original words back.
- **The child-safety hold is the only place household content is kept for
  reporting.** When input moderation flags `sexual/minors`,
  `hold_nina_chat_run_for_child_safety` seals the message in
  `private.child_safety_holds` (no role reaches it), keeps it out of normal
  message storage, blocks the account's chat (`nina_ai_blocks`,
  `child_safety_hold`), answers with the generic refusal and logs only
  `child_safety_hold_created` and the run id. The hold carries the account and
  house ids with no foreign key, and an account deleted while a hold is inside
  its preservation period (open, or receipt confirmed less than 6 months ago,
  UNVERIFIED pending the MJSP act) is first copied into the sealed
  `private.child_safety_preserved_accounts` (Apple `sub`, email, sign-in dates,
  memberships, chat and memories); a house deletion takes the same copy first
  for every account the house held or that wrote in it, and every later copy
  of that account is merged into the first, never dropped (`202610150001`);
  the deletion then completes, and the block
  follows a new account signed in with the same Apple ID while the hold stands.
  Retention drops a preserved account once its hold leaves the period, a false
  positive at once. The rest is `docs/child-safety-runbook.md`. A reported reply is kept past normal retention
  through `held_for_review_until`, at most 90 days. When the house is deleted
  inside that window, `delete_household` first copies the reply and the
  message that asked for it into the report (`nina_reply_reports.reply_text`
  and `request_text`, migration `202610150001`), because the cascade takes
  both messages and the run, and `run_nina_retention` clears the copies 90 days
  after the report; only the reporter still erases a held reply early, and
  once the house is gone that means deleting their account
  (`prepare_account_deletion` clears the copies on the person's own reports).
  The person whose action deletes the house gets no copy of their own
  reports, since the deletion takes their conversation as clearing it would.
- **Every `/v1/responses` call carries `safety_identifier`**, hex SHA-256 of
  `NINA_SAFETY_ID_SALT` ‖ user id. It is never logged, and a missing or short
  salt refuses the turn with `503 service_not_configured`.
- **Chat threads are per-adult, not per-family.** `nina_threads` is unique on
  (family_id, owner_user_id); one adult's private conversation must never reach
  another adult's context, tools, or weekly insight.
- **Memories start private.** Sharing is always a separate, explicit tap
  ("Guardar para mim" vs "Compartilhar com a casa"), never a single accept.
- **A child's or pet's "O que a Nina lembra" is read, never typed.** The member
  editor collects no note for either, and saving one writes `memory_note = ''`.
  A typed note about a pet therefore stops reaching `nina-chat`; a child's never
  did (`minimizeMembersForModel`). The card is `MemberRecollection.summary`,
  built on the device from what this viewer can already read: memories whose
  title or body name the member, and the member's open repeating tasks with
  their rhythm. It never shows a memory's body or `task.subtitle`, and never
  another adult's private memory, even one left in the cache. A name matches as
  whole words with accents and case folded, and the longest household name
  wins, a person's full name included: the father João Pedro Silva's "João
  Pedro" never reaches his son Pedro. A name two people share credits nobody,
  and neither does Nina's own.
  Locked by `MemberRecollectionTests.testNothingFromATasksDetailReachesTheSummary`
  and `…testAnotherAdultsPrivateMemoryNeverReachesTheSummaryEvenWhenItIsOnTheDevice`.
- **`store: false` on every OpenAI call, and no prompt-cache write on
  `gpt-6-luna`.** OpenAI stores no response. GPT-5.6 and later cache implicitly:
  left alone, every request writes the whole prompt, household context and the
  person's message included, to a prompt cache that lives at least 30 minutes
  ("OpenAI may retain it longer") and is billed at 1.25× input. So every
  `gpt-6-luna` call sends `prompt_cache_options: { mode: "explicit" }` and places
  no breakpoint, which means no cache read and no cache write (verified live
  2026-09-23: `cache_write_tokens: 0`). The prefix every turn shares
  (instructions, tools, schema) is under the 1,024-token cache minimum, so the
  cache was only ever read back inside a tool-call turn; repriced on the eval's
  token counts, a turn is about 7% cheaper without it. `gpt-5.4-mini` answers
  the parameter with 400 `invalid_parameter`, so the insight fallback does not
  send it and keeps that model's older in-memory cache (minutes). Asserted by
  source-scanning tests.
- **The monthly budget is a database CHECK**, not application logic:
  `reserved_microusd + spent_microusd <= cap_microusd`, US$20/mo interactive +
  US$5/mo insights. Reserve-then-settle: failed runs must still book actual
  spend (`record_failed_nina_ai_run`), or induced failures run past the cap.
  A reservation must never be smaller than the run it covers: GPT-5.6 and later
  bill prompt-cache writes (`cache_write_tokens`) at 1.25× input, so
  `estimateMaximumCostMicrousd` prices every input token at the higher of the
  input and cache-write rates, and `calculateActualCostMicrousd` books writes at
  their own rate. Nina's `gpt-6-luna` calls turn caching off (above), so writes
  should read zero; the accounting stays so a regression is still paid for.
- **A run settles against the month it reserved in**, read from
  `nina_ai_runs.budget_month_start`, never from `current_month_start()` at
  completion. `current_month_start()` belongs only on the two reservation paths.
  Recomputing it at settle time strands the reservation of any run that crosses
  midnight on the last day of a month, permanently shrinking that month's cap.
- **Logs are content-free.** Only run ids, model, token counts, cost, latency,
  and stable codes. A test greps every `console.info(JSON.stringify({…}))` and
  fails if it references `body.message`, `assistant_reply`, `attachments`, or
  `structured.reply`.
- **Insight prompt constraint:** *"Não atribua culpa, intenção, saúde mental ou
  valor moral."* You cannot show a couple a fairness chart without it becoming a
  weapon; the prompt is where that is prevented.
- **Only Nina writes an insight.** `household_insights` rows come from
  `complete_nina_insight_run` alone; `authenticated` holds `select` and the one
  policy is `for select` (migration `202609260003`, applied 2026-09-26). Until
  then a member held full DML under a `for all` policy, so either adult could
  forge or rewrite the weekly insight the other reads as Nina's, blame
  included, and the prompt constraint above meant nothing. The exact grant map in `rls_policies.test.sql` pins the grant,
  and a temporary re-grant there proves the policy alone still refuses.
- **Only the server writes a chat line.** `chat_messages` rows come from
  nina-chat's RPCs alone; migration `202609260004` (applied 2026-09-26)
  leaves `authenticated` with `select` and drops the "Legacy chat messages
  remain family writable" `for all` policy. Before it, any member could insert
  a legacy row (`thread_id is null`) with `sender = 'nina'` and any text, or
  rewrite and delete another member's.
  The app no longer writes one: a turn the server did not record and the
  "Você confirmou" line from `applySuggestion` stay on the phone, and
  `RemoteHomeBackend` has no chat write at all. Locked by
  `AppStoreAuthorizationTests.testALegacyTurnAndItsConfirmationStayOnThePhoneAndOnlyTheTaskReachesTheServer`
  and the grant map and re-grant in `rls_policies.test.sql`. TestFlight builds
  1–8 still send that confirmation when someone taps the card on an offline
  reply; that one write now fails with "Não foi possível sincronizar a
  confirmação da Nina." while the task itself syncs.
- **A portrait the snapshot refused to conclude is never drawn.** `HouseholdWorkload`
  returns an inconclusive snapshot below 6 assigned open tasks or 2 adult carriers, but
  that snapshot still carries a fully populated `entries` array — so both render
  sites (`TodayView.overloadCard`, `HouseView.workloadCard`) gate `WorkloadBars`
  and the "não para cobrar" caption on `snapshot.isConclusive`, not on
  `hasAnyLoad`. Rendering bars beside "Ainda sem retrato da casa" reads as the
  app accusing someone and then denying it.

### Secrets & data protection

- **No server credential in the iOS binary, an xcconfig, the Info.plist, or any
  `PUBLIC_*` web variable.** Enforced four ways: `repository.secret-content`,
  `artifact.credential-scan`, `artifact.publishable-key`, and
  `SupabaseConfiguration` refusing at runtime to build a client from an
  `sb_secret_` or non-`anon` JWT. A shipped service-role key cannot be revoked
  from installed binaries.
- **Sensitive local data never goes in `UserDefaults`.** Household snapshot,
  profile + photo, AI consent, pending invite, a minor's usage ledger
  (`PrivateLocalDataScope.minorUsage`), the last regulatory-feature set the
  age check saw (`.ageAssurance`) and the given name Apple shared until the
  person is named (`.sharedAppleName`) → `PrivateLocalDataAccess` or the store
  itself → `ProtectedLocalDataStore`: SHA256-opaque filenames,
  `completeUntilFirstUserAuthentication`, `isExcludedFromBackup`, 32 MB cap.
  Legacy defaults are removed *only after* the protected write succeeds.
- **Account deletion order is photos → `prepare_account_deletion` → Auth user**,
  each stage aborting the next on failure, plus a `BEFORE DELETE` trigger on
  `auth.users` that re-runs the preparation idempotently to close races. Every
  path runs it — a person's own, a guardian's and nina-maintenance's — through
  `deleteAccountInOrder`. `prepare_account_deletion` never hands a house to
  anyone who is not an adult today; with no adult successor the house is
  deleted at once.
- **Anyone signed in can delete their account, with or without a house.**
  `AccountDeletionView` is reachable from the Ajustes root and, through
  `.accountDeletionSheet`, from `AgeCheckView` (the first screen after sign-in
  since build 11), `HomeSetupView`, the pending and access-decision screens,
  `HomeAccessUnavailableView`, the majority and Terms gates and every minor
  screen (App Store 5.1.1(v); build-10 fix d). Since build 11 a failure is typed
  (`AccountDeletionFailure`, mapped from delete-account's stable code, or, for an
  answer with no code, 401 → session ended, 408/429 → temporary, other 4xx →
  refused, anything else → unconfirmed) with one short line each, kept in
  `AuthSessionStore.deletionFailure` and never in the shared `errorMessage`, so
  it cannot bleed onto other screens. "Nada foi apagado" is said only where it
  is provable: a cancelled Apple sheet (nothing sent), no internet (an
  `NWPathMonitor` check before sending found no path, or DNS or the TCP connect
  failed; a mid-flight `-1009` is unconfirmed) or a 4xx refusal before any stage
  ran. A gateway 5xx or a dropped connection may come after the function
  finished, so it reads "A resposta não chegou. Tente de novo."; a signed-out
  reply right after it reads "A conta pode já ter sido apagada.", never "entre de
  novo" (signing in again would open a new account), with a quiet "Sair" that
  wipes this phone like a finished deletion. A refusal, an ended session, or the
  second failure in a row (a cancelled Apple sheet counts, so a sheet that never
  completes still reaches it) adds "Para apagar mesmo assim, escreva para
  privacidade@ninai.app." with a quiet "Escrever" mailto whose body carries only
  references: "Referência: <account id>", or a ward's member id plus the
  guardian's own "Responsável: <account id>". A guardian refusal never offers
  it. **A reference finds an account and never proves who wrote**: every adult
  of a house can read every member's ids, so the operator deletes only after the
  sender proves control from inside the account (runbook §2, "Deletion requests
  by mail": a mailed one-time code typed as the Perfil name, plus
  `authorize_guardian_account_deletion` for a ward); a minor's or unknown-age
  account's own mail is never acted on alone. Locked by
  `AuthSessionTests.testOnlyALineThatCanProveItSaysNothingWasDeleted`,
  `…testARefusalOffersTheMailWayOutAtOnceAndATemporaryFailureOnlyFromTheSecondInARow`,
  `…testOneCancelledAppleSheetSendsNothingAndARepeatedOneReachesTheMailWayOut`,
  `…testASignedOutReplyAfterAnAnswerThatNeverArrivedReadsAsMaybeDeletedAndNeverSendsThePersonToSignIn`
  and the Deno "the app matches every delete-account error code whole".
- **`delete-account` accepts exactly one of three bodies**:
  `{"confirmation":"delete"}`, the same plus `"apple_authorization_code"`, or
  `{"confirmation":"delete","member_id":"<uuid>"}` from a live guardian of a
  claimed minor (authorized by `authorize_guardian_account_deletion`,
  service_role only; `403 guardian_access_denied` otherwise). The app never
  stored Apple's first authorization code, so it asks Apple for a fresh one at
  deletion time (`AppleDeletionReauthorizer`, no scopes): a cancelled Apple sheet
  sends nothing, and any other Apple failure or a different Apple subject sends
  the bare body.
- **The Sign in with Apple token is revoked only after the account is gone.**
  `_shared/apple-sign-in-revocation.ts` signs an ES256 client secret on WebCrypto
  with the `.p8` key from Edge Function secrets (`APPLE_SIGN_IN_TEAM_ID`,
  `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_PRIVATE_KEY`; client id
  `com.heitor.nina`), exchanges the code and calls `/auth/revoke`. A failure
  never blocks, undoes or changes the answer to a deletion: it is logged as
  `apple_token_revocation_failed` with the request id and a stage
  (`configuration`, `token_exchange`, `revoke`) and nothing else. **The key never
  enters the repository, a test or a log**; tests sign with a key generated at
  run time. A guardian deletion carries no code, so that ward's Apple token is
  not revoked. The app also removes the App Attest key id from the Keychain on
  deletion.
- **The waitlist unsubscribe token lives in the URL fragment and nowhere else**:
  `https://ninai.app/unsubscribe/#<token>`. A path or query would put a live
  cancellation capability into HTTP access logs.
- **The waitlist never confirms whether an address exists**, and unsubscribe
  never confirms whether a token was valid. Both always return
  `202 {accepted:true}`. Any deviation is an email-enumeration oracle.
- **The raw client IP never leaves the Worker** — only `SHA-256(salt ‖ IP)`.
- **Misconfiguration fails closed, never guesses.** No production fallback
  endpoint or key, anywhere.
- **A child's list carries a task's title, hour and category glyph, nothing
  else.** The child's full-screen list, the printed page and the shared picture
  and PDF are all built from `ChildDayRow`, which has no field for the task's
  detail line, so a photographed boleto's reading can never reach a child, a
  printer or a WhatsApp chat. Locked by
  `ChildDayTests.testARowCarriesTheTitleTheHourAndTheGlyphAndNothingElse` and
  `…testNothingFromATasksDetailReachesTheListThePrintoutOrTheSharedPicture`,
  which reads the picture's words back off a PDF of the same view.

### Monetization

- **A purchased transaction is not `finish()`ed until the server records it**,
  or StoreKit loses the redelivery path.
- **Only an account whose `may_buy_premium` is true buys Premium.** The paywall is
  reached only through `PremiumEntryView` for an account whose age status allows
  it, and `premium-subscription-sync` refuses a new original transaction from
  anyone else with `403 premium_requires_adult` (renewals already recorded are
  honored); the app leaves such a transaction unfinished
  (`PremiumBackendRequestError.premiumRequiresAdult`).
- **Deleting an account never looks like cancelling a subscription.** An active
  subscriber sees "Sua assinatura continua." / "Apagar a conta não cancela a
  cobrança. A Apple segue cobrando até você cancelar." and "Gerenciar
  assinatura" (StoreKit `showManageSubscriptions`, URL fallback) before the
  typed gate (build-10 fix b).
- **`.appAccountToken(user.id)` on every purchase**, and
  `premium-subscription-sync` rejects `appAccountToken !== auth.uid()` with 403.
  Apple's JWS is validly signed for *someone* — the token is the only thing
  binding it to a Nina account.
- **A family-shared transaction never reaches the server and never reads as
  premium on the device.** Both subscriptions have Family Sharing on in App
  Store Connect (turned on 2026-09-03; Apple does not allow it to be turned off
  again), but Nina's sharing unit is the household, not the Apple family: the
  server binds every receipt to the buyer's `appAccountToken`, so a shared
  receipt would only ever produce a 403. `PremiumLocalTransaction.isFamilyShared`
  gates both feeders (`latestUsableLocalTransaction` and the
  `Transaction.updates` listener). Locked by
  `PremiumSubscriptionTests.testAFamilySharedTransactionIsNeverSentToTheServerAndNeverReadsAsPremium`.
- **Production verifies production first, then sandbox — never pinned to
  `production` (decided 2026-09-26).** `NINA_APP_STORE_ENVIRONMENT` stays
  unset, at launch and after it: App Review buys with the release build in
  Apple's sandbox, so a production-only server refuses the reviewer's purchase
  and fails Guideline 2.1. Xcode and LocalTesting receipts carry no Apple
  signature and are never accepted implicitly; an unrecognized value throws
  rather than degrading. A sandbox receipt covers only its buyer's house
  (`appAccountToken`), is recorded with `environment = 'Sandbox'`, and lapses
  on Apple's accelerated test clock; the cost is free premium for every tester,
  so a public TestFlight link always carries a tester limit and is turned off
  when the round ends. `environment.app-store-mode` fails the
  preflight if the variable is set at all. The reasoning is in
  `docs/premium-flow.md` §6.

---

## 5. iOS app

### State layer

`@MainActor @Observable final class AppStore` is the single central store
(2,468 lines). Dependencies are protocol-typed and `@ObservationIgnored`;
`BackendServices.make*` in `Nina/BackendConfiguration.swift` is the only
resolver. Seven stores are injected once in `NinaApp.body`; views read them via
`@Environment(AppStore.self)`.

**Concurrency has no actors and no locks — correctness comes from re-validating
after every `await`.** Four mechanisms, all of which you must preserve:

1. **Context token.** Capture `let contextToken = currentHomeContextToken`
   before any suspension; `guard isCurrentHomeContext(contextToken) else { return }`
   after *every* await. `homeContextGeneration &+= 1` invalidates in-flight work
   on sign-out or account switch.
2. **Serialized write queue.** `enqueueRemoteMutation` chains via
   `await previousTask?.value` for FIFO remote writes. Parallel writes would
   reorder against server row versions.
3. **Local revision guard.** `refreshHomeFromRemote` snapshots `localStateRevision`
   and refuses to apply remote state if the user edited mid-flight.
4. **Debounced realtime.** `AsyncStream<HomeRealtimeEvent>`, 2s reconnect,
   180ms debounce, awaits pending mutations before refreshing. Each
   subscription joins a topic of its own (`realtimeTopic`, family id plus a
   UUID): supabase-swift hands back any channel still registered under a topic,
   even one being torn down, and binds nothing to a channel already joining,
   so the second activation of every cold launch used to get a dead channel
   and Casa saw a join request only after a relaunch (fixed 2026-10-15). The
   stream also ends when its channel leaves `.subscribed` or the socket leaves
   `.connected`, because the client never rejoins a channel it still counts as
   joined, and the 2s loop subscribes again. Two activations for one account at
   once share one (`homeActivation`), a refresh asked for while another sync
   runs is read when that sync ends (`refreshRequestedWhileSyncing`), and
   Casa, Hoje and Tarefas pull to refresh through `refreshHome()`. Every join
   yields `.subscribed`; the store ignores the first one (the activation just
   read the house) and reads the house once on every rejoin, so a change made
   while the last channel was down is never lost. A refresh that lands on a
   house starts the listener again when none is running for it
   (`realtimeFamilyID`): an unverifiable load stops it, and before that rule a
   later good load (a return to the app, a pull) left the session with no
   realtime at all, and a pending adult let in on a refresh never got any.

Copy the standard method skeleton verbatim for anything new: capture token →
clear `syncErrorMessage` → branch on backend availability → `isSyncingHome = true`
with `defer { finishSyncingHome(ifCurrent:) }` → re-check the token after each await.

**Root routing** (`AppEntryRouting` in `AppRootView.swift`, a pure function
of `AppEntryInputs`) evaluates in strict order: `signedOut` → `ageCheck` →
`homeLoading` → `homeUnavailable` → `minorRoot` (any viewer whose age status is
not adult; the four-tab container is never mounted for them) → `majority`
("Agora a conta é sua.", once, when Apple confirms an ex-minor is 18) →
`termsAcceptance` ("Os Termos mudaram.", or "Antes, os Termos.") → `invite` →
`pendingApproval` / `accessDecision` / `homeSetup` / `tutorial` (an adult whose
house is authorized and who has not seen it on this phone, or asked to again) /
`app`. A failed membership check reads as unavailable before the minor check,
because a failed verification leaves age unknown and must not show a minor
screen. `ageCheck` appears only when the server holds no age row
for the account, on `recheck_after`, or when `requiredRegulatoryFeatures`
changes; Apple errors are never recorded as an answer. Sign in with Apple asks
every account the same, for the name alone, so nothing about the person is
decided before sign-in: the age range is read afterwards by `ageCheck`, the
first screen a new account sees, and an adult who shared a given name reaches
house setup with no name field (§4, "A house member is named by the person").
Locked by
`AppStoreAuthorizationTests.testTheAgeStepComesBeforeTheInviteAndTheTutorial`,
`…testAMinorAccountLandsOnItsOwnTasksAndNeverOnTheFourTabs`,
`…testAMinorNeverReachesTheChatThePaywallOrTheWorkloadPortrait` and
`…testAnAppleFirstSignInRecordsTheFootnoteOnlyOnceTheAgeReadsAdult`.
`homeSetup` opens on a choice, "Criar uma casa" or "Tenho um convite", with no
field focused, so a partner whose invite link was lost on the way to the App
Store does not open a second house by accident (rubric O9, since 2026-10-15);
the invite screen's second button reads "Criar uma casa" only for someone with
no house and opens setup on the create path (`InviteSetAside`), and "Agora não"
for anyone else (`AuthSessionTests.testHouseSetupOpensNoKeyboardUntilThePersonChoosesToCreateOrJoin`,
`InviteLinkTests.testOnlySomeoneWithoutAHouseIsOfferedToCreateOneInsteadOfJoining`). Four tabs
(Nina / Hoje / Tarefas / Casa) in a **custom container, not `TabView`**, each
with its own `RouterPath`. **Tabs change only by tapping the bar** — the
horizontal swipe between tabs was removed on 2026-09-23 because it caused
mis-taps and stole the back gesture, and a tap on the bar switches instantly,
like `UITabBarController`. Only a jump from inside a screen ("Conversar com a
Nina", the "Sem dono" shortcut) animates, through `travel(to:)`: a short
cross-fade with a slide that Reduce Motion removes. All four tabs stay mounted. **The system edge swipe-back
works on every pushed screen, sheets included,** through the
`UINavigationController` extension at the end of `AppRootView.swift`: the
navigation bar is hidden app-wide, which otherwise disables
`interactivePopGestureRecognizer`, and its `viewControllers.count > 1` guard is
what keeps a swipe on a root screen from freezing the stack. A child's member
screen can hand the phone over — any adult of the house may "Mostrar" an
account-less child's list once a guardian has consented, and only a live
guardian prints or shares it: `ChildTodaySection` sets
`AppStore.childDayPresentation`, and `AppRootView` presents `ChildDayView` from
its root as a `fullScreenCover`, so neither a lost home nor a tab reset can
close it. It closes on a 2-second hold, or in one step through VoiceOver (the
hold button's default action and the escape gesture), which must stay; it
carries no share or print, and draws its own app-switcher cover (the same
`AppLoadingScreen`, without the rating) because the root one sits beneath it.

**Age on the device.** `Nina/AgeAssurance.swift` holds the fail-closed
`AgeStatus` decoder, the `AgeSignal` that writes the canonical 7-key JSON
(sorted keys, explicit nulls), the `AgeAssurance.map` mirror of
`_shared/age-assurance.ts` (both tested against the same table), the
`AgeRangeProviding` protocol and `DeclaredAgeRangeProvider` (gates 12, 16, 18;
`.confirmed` only behind `#available(iOS 26.5, *)`), and `AgeCheckCoordinator`.
`Nina/AppAttestClient.swift` keeps one App Attest key id per install and user in
the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never
`UserDefaults`, and re-registers once on `app_attest_key_unknown` or when the
device lost the key (`DCError.invalidKey` on a stored key id: App Attest keys do
not survive a reinstall or a restore, while that Keychain item can); a server
outage never discards the key. A DEBUG build
against a loopback stack uses the `insecure-local` key id when App Attest is
unsupported (the Simulator); nothing else ever does. Everything is resolved
through `BackendServices.makeAgeRangeProvider` / `makeAgeSignalSubmitter`. The
minor experience is `MinorViews.swift`, the guardian sheets and supervision
block are `GuardianViews.swift`, and the rating constant is `NinaRating.swift`.
A share started from a button inside the app ("Tentar de novo" on the chat's
age gate, "Compartilhar faixa", "Compartilhar de novo") goes through
`AgeCheckCoordinator.requestInline`, which routing never sees: the screen stays
and shows the outcome in one line. Only the first-run prompt and the launch
recheck take over the root. **The Terms are accepted only where they were
shown**: the welcome footnote, under the one Apple button, counts for a sign-in
made there (`AuthSessionStore.interactiveSignInUserID` →
`AppStore.noteTermsFootnoteShown`), and its acceptance is recorded once the age
step reads adult. The footnote is kept in `ProtectedLocalDataStore`
(`PrivateLocalDataScope.termsFootnote`) until the server records it, so a kill
or relaunch between Apple's sheet and the age answer keeps it; one read back
after a relaunch counts only for Terms whose `current_terms_version` (a
`yyyy-MM-dd` date; keep it one, and since 2026-10-15 the date the Terms page
shows) is on or before the São Paulo day it was shown,
and it is dropped when the account changes or signs out. A restored session of
an adult who has not accepted the current version lands on "Os Termos mudaram."
(`AgeMajorityView`, reason `.termsChanged`) until they tap Aceitar; a footnote
whose recording failed lands on "Antes, os Termos." (`.termsNotYetRecorded`),
because nothing changed for that person. Locked by
`AppStoreAuthorizationTests.testAWelcomeFootnoteSurvivesARelaunchBeforeTheAgeIsReadAndIsRecordedOnce`,
`…testAFootnoteShownBeforeTheTermsChangedIsNeverRecordedAndTheGateSaysTheyChanged`
and `…testAFootnoteWhoseRecordingFailedAsksAgainWithoutSayingTheTermsChanged`. That screen and the majority
screen both carry "Sair da conta" and "Apagar conta".

**Models.** Every persisted/synced model has a hand-written `init(from:)` using
`decodeIfPresent(...) ?? default`. New fields must be additive with a default,
never required. Models crossing the Supabase boundary use snake_case
`CodingKeys`; locally-cached-only models stay camelCase.

`TaskItem` carries both `dueLabel` (pt-BR display string) and `dueAt` (Date) in
parallel, plus `version: Int` for optimistic concurrency. Recurrence expansion
lives on the model (`scheduledOccurrence(after:)`).

### Design system

The design system is **azulejo**, built from the 47 Paper boards on 2026-08-12.
The direction is in `docs/rebrand-azulejo.md`, the QA in `design-qa-azulejo.md`,
and **every departure the build makes from the boards is in
`docs/rebrand-implementation.md`** — read that before assuming a screen is wrong.

**`Nina/Theme.swift` is the only source of color, and the palette is light-only.**
`NinaApp` pins `.preferredColorScheme(.light)`: the glaze has no designed dark
counterpart, so there is no `dynamic(light:dark:)` layer and no colorScheme
branching anywhere.

- `ground #FBFCFD` every screen · `grout #EDF0F4` fields and inactive chips ·
  `line #DFE4EB` hairlines and card strokes · `ink` · `muted` · `faint`
  (uppercase letterspaced labels only, 12px floor).
- `cobalt #1B4FD8` is brand, Nina and commit — **one cobalt control per screen**.
- `terracotta #C2410C` is **lateness only**. Never destruction, never offline,
  never a category. Destruction is carried by weight and friction (ink fill,
  terminal position, a typed gate); in an editor, the quiet "Apagar" sits in the
  commit row opposite the commit (edit mode only, read after it by VoiceOver,
  ending the field column at accessibility sizes); blocked, empty and offline
  states use grout + ink.
- `alert #D92D20` (text `alertInk`, ground `alertWash`) is **errors only**,
  since 2026-10-04 (Heitor: an error reads red, a success green): a failed
  write, a refused step, a field to fix. Always through `NinaErrorNote` or the
  sync toast, so the `exclamationmark.circle.fill` glyph travels with it.
  The one other use is the Urgente flag (`priorityUrgent`, below), which is a
  flag glyph and never text or a ground.
  Never lateness, never destruction, never a blocked or empty state. A step a
  person completed may answer in moss (`NinaSuccessNote`, the undo toast).
  A failure line opens one way, "Não deu para ‹ação› agora. Tente de novo."
  (rubric G20, 2026-10-15); the sign-in line "Não foi possível entrar agora.
  Tente de novo." keeps its words because §12 and the runbook quote it.
- `moss #3F6B4A` marks confirmed/done, and only for something a *human* confirmed.
- **Category is a monochrome outline glyph, never a colour** (kids mode is the
  one exception, §4 "Kids mode is presentation only"). `MemberTone`'s case
  names are wire values that outlived their hues; they render as neutral ink tints.
- **Priority is a tinted row on a list and a coloured flag on the detail**
  (since 2026-10-15, Heitor: "Urgente" and "Alta" changed nothing on the
  list). Every open task row in Hoje, Tarefas (selection included) and a
  child's section sits on a rounded ground (`PriorityFlag.rowTint`, radius
  12, 10 pt past the row's sides, 2 pt in from its top and foot): light red
  `priorityUrgentWash #FDE2E0` for Urgente, light yellow `priorityHighWash
  #FEF6C7` for Alta, none for Normal or a done task. No hairline runs along a
  tinted row (`PriorityFlag.showsDivider`), and VoiceOver reads the title as
  "Urgente, …" or "Prioridade alta, …". Beside "Prioridade" on the task's
  detail `PriorityFlag` still draws a red filled flag for Urgente
  (`priorityUrgent`, the `alert` red) and a light yellow one with a darker
  edge for Alta (`priorityHigh #FACC15`, `priorityHighEdge #A16207`; a light
  yellow alone reads 1.5:1 on the ground, the edge 4.8:1). Build 16 put an
  ink flag before the title and build 17 coloured it; Heitor tested build 18
  and on 2026-10-19 chose the tinted row from two mockups (tinted row, flag
  after the title). Colour stays off the category glyph, the date and the
  title: lateness is still terracotta and only the date says it
  (`TaskAgendaTests.testAnOpenUrgentOrHighRowIsTintedWithNoHairlineAlongItAndADoneOrNormalRowIsNot`,
  `…testAnUrgentTaskCarriesARedFlagAHighOneAYellowFlagWithAnEdgeAndANormalOneNone`).
- **The app draws no ClassInd rating pictogram (since 2026-10-19, build 19).**
  `NinaTheme.classInd(_:)` / `classIndLivre` and `ClassIndMark` still hold the
  official colours and the drawing, so putting it back is one call on each
  screen, but nothing in `Nina/` calls `ClassIndMark` and
  `repository.rating-mark-placement` fails the preflight if anything does.
  From build 11 to build 18 the mark sat on `LoginView` and the startup
  `AppLoadingScreen`, because Portaria MJSP 1.048 art. 50 reads: "A exibição
  das indicações etárias e dos descritores de conteúdo nos aplicativos e
  navegadores deverá ocorrer nas páginas de instalação, login e inicialização
  ou carregamento" (in force since 2026-03-17; art. 48 V plausibly covers
  Nina's chat, and Lei 15.211 art. 8 V asks the same of a service minors may
  reach). Heitor removed it on 2026-10-19 after a search found no app,
  Brazilian or not, that shows its own rating on a login, splash or settings
  screen (stores show it on the listing; streaming apps show it per title).
  The risk he took: an ECA administrative infraction (Portaria art. 13), with
  no enforcement found, while the análise prévia's analyst will open the app.
  Terms §4, `/familias/` §11, the site's footer and the App Store listing
  still carry the rating. The hexes and the drawing are UNVERIFIED against the
  gov.br/mj artwork (`docs/rebrand-implementation.md` §6i).
- **A wait is `AppWaitingScreen`**: the 64pt `.rest` mark and "Só um instante.",
  centred on the whole screen, breathing only without Reduce Motion. `.reading`
  (the disc stretched to a bar) belongs only to the chat's "Lendo" bubble; used
  for a generic wait it read as a squashed disc.

**Typography:** Fraunces (bundled, `Nina/Fraunces-Regular.ttf`, 45 KB, OFL) for
brand voice — screen titles, Nina's own speech, the one big number, **never a list
row**. SF Pro for interface. Always through the modifier:
`.ninaText(.screen)` / `.ninaText(.label, NinaTheme.muted, weight: .semibold)`.
Raw `.font()` on user-facing copy is off-convention.

**The mark.** `NinaMark(size:presence:)` — an open cup holding a disc it never
closes over. Two masters (64 and 24) that differ by measurement, not by scale;
below 18pt the cup retires and the disc ships alone. It never rotates, never
closes, never sits inside a badge, and never takes terracotta. Presence is a
position, never an expression — she has no face because a face watching a
household is what this product refuses.

**Layout rules that hold everywhere:**

- Screen: `ScrollView { VStack(alignment: .leading, spacing: …) { … }
  .padding(.horizontal, 20).padding(.bottom, 104) }.ninaScreenBackground()`.
  Screens draw their **own header**; the navigation bar is hidden app-wide and a
  pushed screen hides the tab bar too.
- Radii: `NinaTheme.Radius` — chip 999, field 14, card 20, sheet 28.
- Cards are **stroked on the glaze** (`.ninaCard()`), not filled boxes with shadows.
- Every custom-styled button carries `.buttonStyle(.plain)`. Universal.
- Disabled states are expressed twice: `.disabled(cond)` **and** `.opacity(…)`.
- Rows: 40pt fixed leading slot + 12pt + title/subtitle + trailing (`NinaRow`);
  matching divider is `NinaDivider()` at inset 52.
- Capture sheets put the **title field first and focus it on appear** in `.add`
  mode (`@FocusState` + `.task { await Task.yield(); isTitleFocused = true }` —
  the yield is required or the assignment lands before the field exists).
  Classification (Tipo, Categoria, Prioridade) always comes *after* the title:
  the user names the thing before the app asks what kind of thing it is.
- **A sheet is as tall as its content** (2026-10-14). Every capture, edit or
  decision sheet is a `FittedSheetLayout` (`SheetFit`, `Sheets.swift`): header,
  scrolling content and bar, with a `.height` detent of their sum (`.medium`
  until measured). It is only ever the root of a presented sheet, never a pushed
  screen, because a detent set from a pushed screen resizes the sheet that hosts
  it. Its header and bar report their own height, and nothing inside it sizes
  from the viewport (no `GeometryReader` sizing, proxy `minHeight`, flexible
  `Spacer` or `maxHeight: .infinity`), or the detent and the layout chase each
  other. A card that reaches full height also loses its side insets, so the
  content's height is read with its width and the card's height is kept there
  (`SheetFit.content(after:height:width:)`), or a note one line from the ceiling
  flips the sheet between card and full height. With the software keyboard up
  the card rides it, chips and commit on the keyboard; the card keeps the height
  its home-indicator inset added (28 pt of the 34 pt inset on a 402 pt phone),
  so the detent gives it back while the keyboard rises (80 ms after
  `keyboardWillShow`, over the keyboard's duration), from the resting bottom
  inset read while the keyboard is down
  (`SheetFit.keyboardSurplus(learned:bottomInset:)`), or that height opens as
  glaze above the chips, the card settles again after it lands, or its top
  dips before the keyboard lifts it.
  `keyboardDidShow` only corrects a difference of 2 pt or more and learns only
  a larger value (a card clamped under the status bar reads a smaller one), and
  the inset is not read while the keyboard moves. A hardware keyboard's
  off-screen frame changes nothing. Where no home indicator lifts it, the bar
  adds space below itself so its commit sits 20 pt from the card's foot
  (`SheetFit.barBottomPadding`, added to the detent, never measured). While
  the fields run under the header or the bar, that edge draws a 1 pt
  `NinaTheme.line` rule (`SheetFit.slicedEdges`), and a card whose fields fit
  draws none. Whether they overflow is read from measured heights, never from
  `onScrollGeometryChange` alone, which skipped the layout a sheet settled on
  and left a clamped card's bar unmarked; the callback only says how far the
  person scrolled. A bar that opens with chips keeps them 10 pt below that
  edge. The header's eyebrow sits between the close disc and an equal empty
  slot, so it wraps rather than run under the disc. An
  editor holding typed input (`hasUnsavedInput` on the task, item and member
  editors: anything typed while adding, any field changed while editing)
  refuses a swipe or a tap above the card (`interactiveDismissDisabled`); its
  close button still discards. `.large` stays only for Settings
  and what it pushes, the paywall, `GuardianApprovalSheet`, the AI consent
  sheet, `MinorSettingsView` and the full-screen covers; `MemberEditorSheet` is
  fitted, and a claimed adult's longer form simply reaches full height.
- **A form's commit follows its last field**, and on arrival the field the
  person types first is focused (not under VoiceOver), so the keyboard fills the
  rest. House setup is the one exception: it opens on a choice with no field, and
  the chosen path's field takes focus (rubric O9). The `Spacer` plus viewport `minHeight` pair is only for a single centered
  block whose exits sit at the foot (the welcome, the gates, the zero states); a
  gate's commit joins its exits at the foot, as on the welcome.
  A short page ends at its last control (rubric G15).
- **`NinaChip` holds one line** below accessibility sizes; a chip row that does
  not scroll horizontally is a `ViewThatFits(in: .horizontal)` with a stacked
  fallback (at accessibility sizes the memory card stacks directly); there a
  lone chip wraps rather than clips (rubric G19).
- **Two labelled buttons share a row only when neither label would wrap.** The
  row is a `ViewThatFits(in: .horizontal)` whose first candidate reports an
  honest ideal width: two filling buttons sit in an `EqualWidthRow` (an `HStack`
  splits them evenly after measuring their sum, which let "Passar" break into
  "Passa / r"), and a filling button beside a short one keeps the short one at
  `fixedSize`. Otherwise the pair stacks, full width; the Tarefas selection
  bar first drops its glyphs, so it holds one row through xxxLarge and stacks
  only at accessibility sizes. An editor's commit row (`EditorCommitRow`)
  gives up the commit's arrow first, then puts the quiet control beside it
  ("Apagar" while editing, "Adicionar e continuar" while adding an item) on
  its own line above the commit; only at accessibility sizes does that control
  end the field column instead, so below them nothing that saves sits ahead of
  the owner chip. A header with a text control beside the title follows the
  same rule (Tarefas' "Cancelar" drops below "Selecionar"; house setup's "Sair
  da conta" moves into its "…" menu).

**Haptics are semantic, not decorative** (`Nina/Haptics.swift`):
`selection()` = navigate/toggle/close/un-complete · `success()` = completion or
successful write · `error()` = validation or network failure (fired from the
store, not the view) · `lightImpact()` = open a sheet or press a chip ·
`warning()` = *arming* a destructive action, right before the confirm alert,
never on the confirm itself. Completing a task fires `success()` but
un-completing fires `selection()` — copy that asymmetry.

**Motion follows the same asymmetry** (2026-10-04): a checkbox pops only when
it closes something; a tapped task row keeps its tick for 380 ms before the
store toggles it, and re-reads the live task first so it never reopens what
someone else closed meanwhile; the `.reading` mark's capsule breathes; a
`.stored` mark's disc drops into the cup on appear; the Nina tab draws the
mark instead of a symbol, and its disc lifts and falls back into the cup each
time a task closes on this phone (`AppStore.completionPulse`, `NinaMark.hops`).
Every one is movement on top of a state that already reads still, and Reduce
Motion removes all five (a row then completes at once). The tour
(`OnboardingTutorialView`, 2026-10-14) plays once per account per phone over an
authorized house, reads no `AppStore` (`repository.demonstration-writes-nothing`),
lands on Nina only for someone who can talk to her, and Reduce Motion or
VoiceOver opens every example on its final frame. Its example house never
borrows a word of any name in the real house (`TourSample.cast(avoiding:)`, fed
the members' names by `AppRootView`), so no real person is drawn in a
workload band or handed a late example task.

**Accessibility:** decorative overlays are `.allowsHitTesting(false)` +
`.accessibilityHidden(true)`. Since 2026-10-05 `CategoryGlyph` is silent unless
given `label:`, `.screen`/`.display` text, `Eyebrow` and `SheetHeader` carry
the header trait, `NinaErrorNote`, the undo toast and Nina's reply announce
themselves, and form fields take their visible title as their name. `reduceMotion` must *disable* ambient animation,
not shorten it. Icon-only buttons need an explicit label. `HouseView` collapses
its grid when `dynamicTypeSize.isAccessibilitySize`. Type is clamped at
`accessibility3` (`NinaApp`, raised from `accessibility1` on 2026-09-09), which
only holds because list rows, chips and buttons size with `minHeight` and every
user-facing string is metered through `.ninaText` — `.compose` (27pt sans) is
the capture title's tier. Since 2026-10-14 `.ninaText` meters its sans face at
the view's own `dynamicTypeSize` (`UIFontMetrics` with a matching trait
collection), so that clamp, and the tab bar's `xxxLarge`, hold for SF as they
already did for Fraunces; before, SF followed the system setting past both. A
primary or outline `NinaButton` keeps 10 pt above and below a label that
outgrows its 50 pt minimum, and a quiet one answers to at least 44 pt across
as well as down ("Pular" alone is 41 pt wide). A raw `.font(.system(size:))` on text is a
regression; on an SF Symbol it is fine.

**On-screen text follows `docs/text-rubric.md`** (2026-09-23, from ~90 Mobbin
references): a header is the title only, a settings row has no description line,
an empty state is one short headline, one short line and one action, and its §3
lists the text that must never be cut (subscription terms, consent, deletion
consequences, "Não ocupa vaga", "Para conversar, não para cobrar"). Run its §0
audit on any new screen. Since 2026-09-29 its **Law-text-gated** rows (the
guardian sheets, the minor welcome and "O que a Nina guarda", the transfer
checkbox, the report channel, the rating mark) each cite the article they
answer in `docs/privacy/avaliacao-impacto-criancas.md` §9; where the legal text
is longer than a word budget, the legal text wins.

**All UI strings are pt-BR literals inline in the view.** There is no
`Localizable.strings`, no `.xcstrings`, no `LocalizedStringKey`. Introducing
`NSLocalizedString` would be a new pattern, not a fix.

---

## 6. Database

55 migrations, `YYYYMMDDNNNN_snake_case.sql`, applied in filename order. Trust
the filename — on-disk mtimes do not match name order. The eight
`202609290001`–`…0008` files (age assurance, minors and guardianship, adult-only
RLS, join and house rules, the minor home view, the AI gates, the insight and
tools without minors, reports/holds/export/retention) are one unit: they are
applied together, in order, before the build that reads them ships
(`docs/production-launch-runbook.md` §3). `202609290009` (the membership
predicates leave the API) is not part of that unit and needs no new build.

**House style for every new object:**

```sql
-- table
alter table public.x enable row level security;
revoke all on table public.x from public, anon, authenticated;
grant select, insert on table public.x to authenticated;  -- only what's needed

-- function
create function public.f(...) ... security definer
  set search_path = pg_catalog, public, auth ...;
revoke all on function public.f(...) from public, anon, authenticated, service_role;
grant execute on function public.f(...) to authenticated;  -- exactly one role
```

Postgres grants `EXECUTE ... TO PUBLIC` on every new function by default. **A
signature change silently creates a new function with fresh PUBLIC rights** —
always re-run the revoke/grant block with the exact new argument list.

Other conventions:

- **No Postgres enums.** Closed value sets are `text` + a named CHECK, altered
  with `drop constraint if exists` / `add constraint` so migrations re-run.
- **Every mutation RPC returns `public.get_current_home_context()`** so the
  client gets one fresh consistent snapshot instead of patching local state.
- **Errors are stable snake_case English strings with deliberate SQLSTATEs**:
  `28000` unauthenticated, `42501` denied, `22023` invalid argument, `23514`
  limit reached, `P0001` business rule, `P0002` not found. Swift and pgTAP both
  match on these.
- **Public responses are non-enumerating.** `get_family_invite_preview` returns
  `{valid:false}` for every failure mode.
- **A predicate whose subject is an argument is granted to no API role.**
  SECURITY DEFINER code calls it as its owner. A policy that must evaluate one
  as the signed-in role gets a caller-only guard instead
  (`auth.uid() is null or target_user_id = auth.uid()`, as in
  `shares_family_with`). New household policies use `is_adult_family_member`;
  `authenticated` cannot execute `is_family_member`, so a policy that names it
  denies every signed-in read with `permission denied for function`. The
  `families` update and delete policies still name `can_manage_family`; they
  were already unreachable, because `authenticated` holds no update or delete
  on that table.
- **Lock order is global: family advisory lock first**
  (`pg_advisory_xact_lock(hashtextextended(family_id::text, 0))`), then row
  `FOR UPDATE`, then re-verify `family_id` still matches.
- **Realtime** requires both `replica identity full` and a DO block adding the
  table to `supabase_realtime` that swallows `duplicate_object`.
- **Grant explicitly. Never rely on Supabase's default privileges.** A freshly
  provisioned database does not apply them, so a table with policies but no
  `grant` denies every access — which is exactly what happened to
  `public.profiles` until 2026-08-08. Any table with a policy `to authenticated`
  needs a matching `grant`, and the grant should be no wider than the policies.
- **Production was created with the opposite defaults.** Until migration
  `202609260001` (applied 2026-09-26) every new public table, function and sequence there granted
  `anon`, `authenticated` and `service_role` everything, so a migration that
  revoked only `from public` left the object open to the publishable key:
  `register_waitlist_signup` and 19 other functions were, while every local
  test passed. `supabase/roles.sql` replays those defaults before the
  migrations on a fresh local or CI database, so the replay reproduces
  production's grants, and that migration then removes the defaults in both
  places. The file does nothing on a database that already has migration
  history, so `db push --include-roles` cannot widen production again.
- **`service_role` holds four table grants, by design.** The two App Store
  functions upsert `premium_subscriptions`, `premium_subscription_transactions`
  and `app_store_server_notifications` directly (select, insert, update,
  delete), and `nina-maintenance` stamps `nina_ai_runs` (select, update). Every
  other privileged server path is a SECURITY DEFINER RPC. Until migration
  `202609260002` (applied 2026-09-26) production's defaults had left it every privilege on every
  public table; the exact service_role table map in `rls_policies.test.sql` now
  fails on a grant extra or missing. If something fails with "permission denied … TO service_role",
  the fix is virtually always to call the RPC (or, in a test, `reset role`) —
  not to add the grant.

`private` schema holds `nina_maintenance_config` (project URL + 32-byte shared
secret) and is revoked from every client role, `service_role` included. pg_cron
runs `nina-daily-maintenance` at `15 6 * * *` → pg_net POST to
`nina-maintenance`. Since 2026-09-29 every new age and minor table lives there
too — `account_age_status`, `age_policy`, `age_signal_challenges`,
`app_attest_keys`, `pseudonym_salt`, `nina_ai_blocks`, `minor_profiles`,
`minor_guardianships`, `minor_data_consents`, `account_terms_acceptances`,
`minor_acknowledgements`, `minor_usage_days`, `nina_reply_reports`,
`child_safety_holds` — so the public RLS canary stays at 27 and
`age_and_minors.test.sql` covers them instead. Guardianship, consent and
acceptance proof is kept 5 years after closing, with user ids nulled on
deletion and `SHA-256(salt ‖ uid)` kept.

**Operator functions are revoked from every API role and run by Heitor in the
SQL editor:** `private.operator_set_age_status(user_id, status, band, trusted,
reason_code)` (resolves an age contest, marks a Simulator or TestFlight account;
records assurance `operator`), `private.operator_lift_ai_block(user_id,
reason_code)` and `private.age_assurance_distribution()` (accounts per status,
band, assurance and parental-controls flag — the D3 measurement, with no birth
date or bound anywhere). `private.age_policy` is one row: `trusted_assurances`,
the three current text versions, and `legacy_profile_deadline`, the date an
unconfirmed pre-release child profile is deleted.

---

## 7. Edge Functions

Six Deno functions, all in production. The all-ages release deployed all six
from commit d26a730 on 2026-09-29 (`age-signal` v1, `nina-chat` v18,
`nina-maintenance` v10, `delete-account` v7, `premium-subscription-sync` v9,
`app-store-server-notifications` v9), from a clean `git archive` export
because iCloud leaves ignored "… 2" copies of source files in the working tree
(§12). `age-signal` v2 (2026-10-04, commit c724166, same clean-export route)
carries the chain-signature fix below. `nina-chat` v19 (2026-10-05, commit
4125c7b, same clean-export route) carries the search over up to 500 ordered
candidates with accents folded, the workload summary without sementes, and a
pet's species and breed in the member context. Before that, `nina-maintenance` was redeployed on 2026-09-23 with the
GPT-6 Luna switch, and `nina-chat` v14 (2026-09-28) carried the bounded body
reader and v12 (2026-09-26) the spoken-dates fix, commit 84ef7c9.
Until 2026-09-23 both still ran the 2026-06-15 build, so check `list_edge_functions` dates against
`git log` before assuming the server runs what the repo says. `verify_jwt`
per `supabase/config.toml`: **true** for `nina-chat`, `premium-subscription-sync`,
`delete-account` and `age-signal`; **false** for `nina-maintenance`
(shared-secret header) and `app-store-server-notifications` (Apple JWS chain is
the only trust).
`delete-account` is the one function that imports `@supabase/supabase-js` by its
bare specifier — its lint task forbids an inline `npm:` prefix — so its
`config.toml` entry carries `import_map = "../deno.json"`; without it the
platform bundler cannot resolve the import and the deploy fails with 400.

- **`nina-chat`** — the assistant turn. Order is load-bearing and asserted by
  "the turn runs in the order the product promises": adult gate →
  `begin_nina_chat_run` (idempotent on `message_id`, claims rate limits, reserves
  budget, and refuses untrusted, blocked or outdated-consent callers) → context
  and `get_nina_model_roster` → `Pseudonymizer` → input moderation on the
  pseudonymized text (child-safety hold on `sexual/minors`) → deterministic
  safety shortcuts, the medical refusal included → token pre-count → model +
  tool loop (every body pseudonymized, `safety_identifier` on every call) →
  `restoreDeep` → output moderation → `fillMissingDueAt` →
  `complete_nina_chat_run`. The context carries `local_now` from the same clock
  the fill uses, and `nina_run_completed` logs `due_at_filled`, the count of
  proposals the fill dated — how often the model alone left a named day null.
  Model `gpt-6-luna` at reasoning effort `medium` (since 2026-09-23; low effort
  lost two cases in the eval) via OpenAI Responses, strict `json_schema`,
  ≤3 proposals, ≤2 extra tool rounds / ≤4 tool calls, 32k input cap, 35s timeout.
  The body is capped at 12 MiB (`maxNinaChatRequestBytes`): the 8 MiB attachment
  ceiling as base64, plus the slashes Swift's `JSONEncoder` escapes. A larger
  body is read to its end and thrown away (up to 32 MiB, see §12), then gets
  413 `input_too_large`, which the app already shows as "grande demais".
- **`nina-maintenance`** — daily retention (`run_nina_retention`,
  `run_waitlist_retention`) *before* any AI work, then the deletion of minor
  accounts that have had no house for 30 days
  (`list_minor_accounts_due_for_deletion` → `deleteAccountInOrder`), then ≤25
  weekly insights on `gpt-6-luna` at effort `low` with a `gpt-5.4-mini` fallback
  (since 2026-09-23; `gpt-5.5` before), each input pseudonymized.
- **`delete-account`** — all logic is in `_shared/delete-account.ts` behind an
  injectable `DeleteAccountBackend`; `index.ts` is a thin adapter. The body is
  exactly one of the three in §4 (self, self with an Apple authorization code,
  guardian with `member_id`); the Apple revocation runs after the Auth delete.
- **`age-signal`** — a thin adapter over `_shared/app-attest.ts` (hand-written
  CBOR and DER parsing, the attestation and assertion checks, the mode rules,
  the injectable handler) and `_shared/age-assurance.ts` (`parseAgeSignalJSON`
  and `mapAgeRange`). Steps `challenge` (32 random bytes, stored hashed, 5
  minutes, single use, 20 an hour), `register` (CBOR `apple-appattest`, the x5c
  chain to Apple's App Attestation Root CA, the nonce extension, rpIdHash of
  `97PL8KQA8L.com.heitor.nina`, counter 0, the production AAGUID) and `signal`
  (the assertion over the stored key, a rising counter, the challenge consumed,
  then `record_age_signal` as service_role). Each step accepts exactly its own
  keys. `NINA_APP_ATTEST_MODE` must be `production`; `development` and
  `insecure-local` are refused unless the project URL is loopback. Every
  signal that leaves an account not adult also removes its profile photos.
  **Chain links are verified with `@noble/curves` on each certificate's own
  DER, never through WebCrypto** (`certificateSignedBy`; `@peculiar/x509` only
  parses). Apple's CA 1 is a P-384 key that signs the device certificate over
  SHA-256, and the edge runtime's Deno 2.1.4 WebCrypto throws "Not implemented"
  for that pairing (and for P-256 with SHA-384), so `age-signal` v1 (2026-09-29)
  refused every real iPhone at `register` (`age_signal_failed`, stage
  `attestation`) while every test passed on the newer local and CI Deno. Two
  real Apple attestations (production and development, from
  `uebelack/node-app-attest`) now verify against the embedded root in
  `app-attest.test.ts`; run that file under a Deno 2.1.4 binary too before
  deploying, because CI never does.
- **`premium-subscription-sync`** refuses a new original transaction from an
  account that may not buy with `403 premium_requires_adult`
  (`premium_buyer_is_eligible`).
- **`premium-subscription-sync`** / **`app-store-server-notifications`** —
  Apple JWS verification via `_shared/app-store.ts`, which delegates the
  cryptography to `_shared/apple-jws.ts`: chain rules, Apple's marker OIDs, and
  the ES256 signature on WebCrypto with `@peculiar/x509`. **Apple's own
  `@apple/app-store-server-library` verifier cannot run in the Supabase edge
  runtime** — it leans on `node:crypto`'s `X509Certificate`, which that runtime
  only stubs (`toString`, `raw`, … throw "Not implemented"), so every real
  receipt failed with an empty message until 2026-09-06. The library stays for
  its payload types only. Revocation (OCSP) is not checked; validity is checked
  against the clock when `NINA_APP_STORE_ONLINE_CHECKS` is `true`, against the
  payload's `signedDate` otherwise.

**Conventions:**

- Pure logic lives in `_shared/*.ts` with a sibling `*.test.ts`; `index.ts` is a
  thin `Deno.serve` wrapper.
- Every error response is `{"error":"<stable_snake_case_code>"}` with
  `Cache-Control: no-store`. **These codes are API surface** — Swift switches on
  them. Never reword one without updating `NinaEngineError`,
  `PremiumBackendRequestError`, `AgeSignalError`, `AccountDeletionFailure`
  (delete-account's codes; the Deno "the app matches every delete-account error
  code whole" fails on drift) or `RemoteRPCErrorCode` (the SQL codes, whose
  pt-BR copy the store owns).
- Wire JSON is snake_case; TS identifiers are camelCase.
- Money is always integer micro-USD, rounded with `Math.ceil`. Never floats.
- Model ids are compile-time constants; only *pricing* is env-overridable, so a
  deploy env cannot silently swap the model. `pricingForModel` throws
  `unpriced_model` for a model without its own branch rather than booking it at
  another model's rates, so a new model needs its price before it can run.
- Bodies are read through bounded stream readers, never `await request.json()`.
  `nina-ai.test.ts` scans every function's `index.ts` and every `_shared` module
  for an unbounded `request.json()`, `.text()`, `.arrayBuffer()`, `.blob()` or
  `.formData()`.

`supabase/functions/_shared/nina-chat-policy.ts` holds the entire system prompt.
**Edits there are product changes, not code changes.** Its brevity is deliberate
— add a rule only when the product genuinely gains one, in Nina's own register,
and pin it with a source-text assertion so a reword cannot quietly drop it.

---

## 8. Web

Astro 7 static build served by a **Cloudflare Worker** (not Pages). Zero UI
framework and, since 2026-08-14, zero icon library; three hand-written vanilla
scripts in `web/public/scripts/` loaded `is:inline` so CSP can stay
`script-src 'self'`. One global stylesheet.

**The site is on the same azulejo system as the app, and light-only for the same
reason.** `web/src/styles/global.css` carries the palette from `Nina/Theme.swift`
verbatim, `NinaMark.astro` transcribes both masters from `Nina/NinaMark.swift`
including the floor gap, and `web/public/fonts/Fraunces-Regular.ttf` is a copy of
the exact cut the app bundles, so the two surfaces render identical letterforms.
Interface type is Inter via `@fontsource`. `Glyph.astro` holds ~20 hand-authored
outline glyphs on the boards' 24 grid: `astro-icon` was removed because
`@iconify/tools` → `extract-zip` carries a high-severity advisory that fails
CI's `npm audit --audit-level=high`. Every deviation from the Paper boards is in
`docs/rebrand-web.md`.

- `wrangler.toml`'s `run_worker_first = ["/api/*", "/invite/*"]` is load-bearing.
  Remove it and the assets layer answers first — the API and the invite rewrite
  break silently in production with no test to catch it.
- `/invite/<code>` is a **200 rewrite** onto the `/join/` shell so the browser
  URL stays put and `invite.js` can read the code off `location.pathname`.
- **Never add an inline `<script>` or `<style>`** — including an Astro component
  `<style>` block, and including a `style="…"` attribute. `style-src 'self'` has
  no `'unsafe-inline'`, so all three are blocked at runtime and `astro check`
  catches none of them.
- **The landing renders whole without JavaScript.** The old `.reveal` gate
  (content at `opacity: 0` until a script cleared it) and its `noscript.css`
  are gone; `home.js` only adds behaviour to a page that is already the
  finished frame. The waitlist buttons still need the script.
  CSP is specified in two places that must stay in sync: `web/public/_headers`
  (static assets) and `securityHeaders` in `web/src/worker.ts` (dynamic).
- Client behavior is bound by `data-*` attribute contracts
  (`[data-waitlist-dialog]`, `[data-invite-status]`), never CSS classes.
  Renaming a class is safe; renaming a data attribute breaks a script.
- **The rating couples web to app.** `web/src/rating.ts`'s `ninaRatingCode`
  must equal `NinaRating.currentCode` (`repository.rating-constant-consistency`),
  and Terms §4, the footer mark and `/familias/` read it; `RatingMark.astro` is
  an inline SVG with presentation attributes only, so CSP stays strict.
  Terms §4 and `/familias/` §11 add a reason clause (`ratingReason`) only
  while the code is `"14"`, so any other code drops the reason silently and
  needs its own sentence (`docs/privacy/classificacao-indicativa.md` §8 step
  2).
  `/familias/` is the App Store Age Suitability URL and `/denuncia/` the
  published report procedure (ECA Digital arts. 16 and 29–33); neither page
  may state a capability the server does not enforce.
- **The FAQ couples web to app.** `/suporte/` (the App Store Support URL)
  renders `web/src/support.ts`, and `web/tests/support.test.ts` fails unless it
  equals `SupportContent.topics` in `Nina/SupportView.swift`, the screen behind
  Ajustes › "Dúvidas e suporte". Change an answer in both, in one commit, and
  keep every answer true of what the server enforces (the quota, the people
  limit, the retention line).
- Two pinned constants couple web to database: `waitlistConsentVersion` and
  `waitlistHealthSchemaVersion` in `web/src/waitlist.ts`. A waitlist migration
  that bumps the RPC's `schema_version` turns `/api/health` red and blocks the
  production preflight until the constant is updated.
- `legal.ts` reads `import.meta.env` at module scope — legal identity is frozen
  at **build** time. Changing a Cloudflare variable requires a rebuild.
- The invite page must never appear to validate a code. An unreachable API
  renders an explicit "Verificação pendente" state (this was a resolved P1).
- **The waitlist receives exactly one email, and not from the Worker.** The
  landing promises "um email só, quando a Nina chegar", so there is no welcome
  mail at signup. The launch send is `deno task waitlist:send`
  (`Tools/waitlist_send.ts`), run from the operator machine with a sending-only
  Resend key: it reads `list_waitlist_recipients` at the instant of sending,
  records each delivery in `waitlist_deliveries`, and a rerun never repeats an
  address. The message needs a numeric `PUBLIC_NINA_APP_STORE_ID`, so it cannot
  be sent before the app is live. Logs carry counts and codes only; a
  source-text test in `Tools/waitlist_email.test.ts` fails if an address, name,
  or token reaches a log statement.

`npm run dev` serves static only — `/api/*` and the invite rewrite do **not**
work there. Use `npm run build && npm run preview` (wrangler dev) to exercise
Worker routes.

---

## 9. Code conventions (repo-wide)

**Comments are rare and all of one kind, and that is deliberate.** Zero `MARK:`,
zero `TODO`/`FIXME`/`HACK`/`WIP` anywhere in the repo. Every comment that
survives is a single line stating a non-obvious **invariant or security
property**, never a description of mechanics —
`// A filled honeypot receives the same generic success as a real submission.`
**Writing explanatory comments here is off-convention.** Put the explanation in
a name, a test name, or a README. The count grows as invariants are discovered
and pinned; what must not change is the kind. If a comment you are about to
write would still be true after the code around it was rewritten differently,
it is an invariant and belongs — otherwise it does not.

**Language split:** English identifiers, English SQL exception codes, English
commits and `docs/`. pt-BR for every user-facing string. `web/README.md` is the
one Portuguese doc (it is an operator runbook).

**Error handling:** zero `fatalError`, zero `try!`, zero force-unwraps in
production Swift. Plain `enum X: Error`; the *view/store* layer owns the pt-BR
copy, not the error type (only `PremiumPurchaseError` and `ProfilePhotoError`
conform to `LocalizedError`). Mutating `AppStore` operations return `Bool`
rather than throwing. Protocol extensions supply fail-closed defaults that
throw `.operationUnavailable`.

**Logging:** Swift `OSLog` with `event=`-keyed `key=value` shapes and an explicit
`privacy:` tag on every interpolation (identifiers `.public`, error text
`.private`). Deno: single-line `console.error(JSON.stringify({ event, … }))`,
event names `<subject>_<verb-past>`.

**Formatting:** no SwiftLint / swift-format / EditorConfig / Prettier config.
Swift is 4-space, hand-enforced, ~100-col soft target. TS and Markdown use
`deno fmt` defaults (2-space, double quotes, 80 col) — but **only for the exact
paths listed in `deno.json`**. Numeric literals use `_` grouping.

**Docs** carry `Last updated: YYYY-MM-DD` directly under the H1 and it is
genuinely maintained. Runbooks are executable prose: a fenced `sh` block with
the exact command, then what it proves and what a failure means. Rationale lives
in READMEs, not code. Design work is recorded as a QA verdict (`design-qa.md`:
compared sources → P0/P1/P2 findings → final checks → `Result: passed`).

---

## 10. Testing

| Layer | Framework | Location |
|---|---|---|
| iOS | **XCTest only** (no Swift Testing, no `@Test`, no UI tests) | `NinaTests/` |
| Database | pgTAP with literal `plan(N)` | `supabase/tests/database/` |
| Edge/worker/tools | `Deno.test` | `_shared/*.test.ts`, `web/tests/`, `Tools/` |
| Web front-end | none — `astro check && astro build` + `npm audit` | — |

**Naming is the documentation.** iOS test names are full behavioral sentences
(`testFailedMembershipVerificationBlocksCachedHomeAccess`), Deno names are
lowercase guarantees (`"account deletion stops before database mutation when
photo cleanup fails"`).

There is **no shared helper module in any layer** — each file declares its own
`private` doubles at the bottom. Duplication is accepted over a shared helper.
iOS fakes are `actor` when they record ordered state, `struct` when they only
throw; recorded interactions are `Equatable` enums so assertions compare whole
sequences. Every persistence test creates a UUID-suffixed `UserDefaults` suite
and temp dir with `defer` teardown (the scheme is `parallelizable = "YES"`).

**Source-text assertions are a real convention here.** Several Deno tests
`Deno.readTextFile` a production file and assert on substrings to pin things no
function signature can express (moderation before the model call, `store: false`,
no `request.json()`, no content fields in log statements, apikey-not-Bearer).
`Tools/production_preflight.ts` generalizes this over the whole working tree.
**These are refactor-fragile by design** — update the assertion deliberately,
never delete it.

**What a contributor writes:**

- AppStore/Auth/Profile/config/model change → a `@MainActor func test…()` in the
  matching existing `NinaTests/` file; reuse or extend the fakes already there.
- Migration/RPC/policy/grant → assertions in the topical pgTAP file **and bump
  its `plan(N)`**. A new public table must be added to the explicit 27-name list
  in `rls_policies.test.sql` or the RLS canary silently passes. A new grant to
  `anon`, `authenticated` or `service_role` must be added to the exact grant
  maps in the same file, which fail on a grant missing and on a grant extra.
- Edge Function logic → put it in `_shared/<name>.ts` behind an injectable
  interface, test in `_shared/<name>.test.ts`, add `index.ts` to `deno.json`'s
  `check` task.
- Worker/Astro logic → extract to `web/src/*.ts`, test in `web/tests/`, add the
  file to `format:web`/`lint:web`.
- New release invariant → a `check(...)` in `Tools/production_preflight.ts` plus
  a `Deno.test` in its test file.

RLS does **not** raise on UPDATE/DELETE — it filters rows. `throws_ok` passes
vacuously; use `pg_temp.affected_rows($$…$$)` and assert 0.

**Every pgTAP fixture that makes a person a member needs an age row.** Since
2026-09-29 an auth user without `private.account_age_status` is unknown, so it
cannot create a house, read a household table or chat. Insert
`('adult', null, 'confirmed', …)` for an adult fixture, as
`account_deletion`, `auth_identity`, `member_management`, `nina_ai_v2`,
`premium` and `rls_policies` do; `age_and_minors.test.sql` holds the minor,
unknown, declared-adult and guardian cases.

**The database gate runs locally — use it.** `docs/local-database.md` sets up a
container runtime once; after that `deno task db:reset && deno task db:test`
replays all migrations onto an empty database and runs the full suite in about
thirty seconds. Every migration below was written before that existed, which is
why the traps read like a list of things CI told someone hours later. Do not
push a migration to find out whether it applies.

Three pgTAP traps that all cost a CI round-trip on 2026-08-08:

- **A file aborts on the first error and blows its whole plan**, reported as
  "Bad plan. You planned N but ran M" with *zero* failed assertions. Read the
  first `ERROR:` line in the log; everything after it is noise.
- **`has_table('public','x')` resolves to the `(table, description)` overload**
  and returns text, so `not has_table(...)` fails to typecheck. Use
  `hasnt_table(schema, table, description)`.
- **A temp table belongs to the role that created it.** Reading a fixture table
  after `set local role service_role` is denied; grant on it or stash the value
  while privileged.

---

## 11. Commands

```bash
deno task check && deno task format:chat && deno task lint:chat && deno task lint:web && deno task lint:deletion && deno task test
```

```bash
deno task preflight:repo
```

```bash
deno task db:runtime && deno task db:up && deno task db:test
```

```bash
deno task db:reset && deno task db:test
```

```bash
xcodebuild test -project Nina.xcodeproj -scheme Nina -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO
```

The scheme is `parallelizable = "YES"`, so without `-parallel-testing-enabled
NO` Xcode boots clones of the destination simulator; one simulator at a time
(§12).

```bash
cd web && npm ci && npm run build
```

```bash
cd web && npm run build && npm run preview
```

Release gates (see `docs/production-launch-runbook.md` for the full seven stages, and its §3 for the all-ages release order):

```bash
npx deno task preflight:production --env-file config/production.env --online --ios-artifact /absolute/path/to/Nina.xcarchive
```

Launch email to the waitlist, once the app is live (dry run first):

```bash
npx deno task waitlist:send --campaign lancamento-2026 --dry-run
```

Local secret files (all gitignored, each with a tracked `.example` sibling):
`Nina/Config/SupabaseSecrets.xcconfig`, `config/production.env`,
`supabase/.env.local`, `web/.dev.vars`.

---

## 12. Traps

Things that will silently go wrong.

**Xcode project.** `project.pbxproj` uses **hand-authored sequential
pseudo-UUIDs** (`F…` file refs, `B…` app build files, `D…` test build files,
`E…` test file refs, `C…` package products), not Xcode's random 24-hex. Adding a
file through the Xcode UI injects a random ID and breaks the scheme. **Edit the
pbxproj by hand, continuing the sequence.**

**xcconfig comments.** `//` starts a comment, so a URL truncates to `https:`.
The tracked example uses `https:/$()/your-project-ref.supabase.co`. Separately,
`BackendConfiguration` rejects any value containing `$(`, so a half-escape fails
closed at runtime. `Nina.xcconfig` ends with `#include? "SupabaseSecrets.xcconfig"` —
the `?` makes it optional, so a missing file yields empty config with **no build
error** (Debug falls back to mock, Release goes `.unavailable`).

**`reminders` is dead.** The table was migrated into `tasks` and dropped;
`ReminderItem` no longer exists. Recurrence and snooze are `tasks` columns. The
only remnant is `LegacyReminderItem` for decoding old local snapshots — removing
it breaks caches written by older builds.

**Demo data is the empty state — locally, not remotely.** `AppStore.init` seeds
every collection from `PreviewData`, and `resetActivityState()` is
`apply(.preview)`. In DEBUG `PreviewData` is the made-up `DemoHouse` ("Casa
Aroeira": Bia, Leo, a child and the dog Biscoito, 7 demo tasks), so any "is the
home empty?" check based on `tasks.isEmpty` is wrong in mock/DEBUG; in Release
it is empty (since 2026-10-15; it used to carry the founder's family). A real remote household does
*not* get demo data: `loadRemoteState` always assigns a snapshot, and `apply(_:)`
only calls `resetActivityState()` when `state.snapshot` is nil. The one surviving
substitution on the remote path is `PreviewData.taskSections` — a single
"Tarefas da casa" section — when the snapshot's sections are empty. So zero
states *are* reachable for real users and must be designed.

**`toggleTask` on a recurring task does not complete it** — it rolls `dueAt`
forward. Only `.none`-recurrence tasks flip `isDone`. A missed
occurrence reads late: `displayDate` returns the latest occurrence at or before
now whenever `dueAt` is in the past, so a daily 21:00 task nobody tapped shows
"ontem, 21:00" in terracotta while the scheduler still books tonight's alert.
Screen and scheduler agree only when nothing was missed
(`TaskAgendaTests.testAMissedDailyTaskReadsAsLateSinceItsLastOccurrence`).

**The child's list never calls `toggleTask`.** `AppStore.markChildTaskDone`
closes every occurrence through today (a daily task missed yesterday moves to
tomorrow, where `toggleTask` would land it on tonight), offers no app-wide undo,
and never raises the edit-conflict sheet — the house's version stands. A second
tap only reopens what the first wrote, through its `ChildDayMark`; a mark the
task no longer matches undoes nothing, and a tap within one second of a change
is ignored. A failed write sets `syncErrorMessage` without the error haptic;
the list hands it back, buzz included, when the adult holds to leave. The
2-second "Segure para sair" hold is a speed bump, not a lock: the home gesture
and other apps' banners still leave, VoiceOver and Switch Control leave in one
step through the button's default action and the escape gesture (those exits
must stay — they are the only ones those users can perform), and Guided Access
is the real lock. What the hold does stop is the app dropping the child into
the adult app on its own: the list is presented from the root and only an
account change clears `childDayPresentation`, so an unverifiable refresh leaves
it open over "Nada para hoje." until the hold. Locked by
`ChildDayTests.testASecondTapOnADoneRepeatingRowReopensItAndNeverSkipsAnotherDay`,
`AppStoreAuthorizationTests.testAChildsListNeverRaisesAnEditConflictAndTheHousesVersionStands`
and `…testARefreshThatCannotVerifyTheHouseLeavesTheChildsListOpen`.

**Child and pet notes typed before 2026-09-26 are still on the server.** Nothing
shows them any more, but `family_members.memory_note` keeps each one until
someone saves that profile. Until then, a pet's note still reaches the model in
`nina-chat`. Clearing them all is a one-off server statement for Heitor to run,
not an app change. Name matching in `MemberRecollection` is also literal. A pet
or child whose name is a common word (Café, Mel, Clara, Rosa) collects every
visible memory that uses the word, and "Pedrinho" or a middle name never
matches. Both only rearrange what the viewer can already read in Memórias.

**Phone, sex and birthday typed with builds up to 13 are still on the server.**
Perfil dropped "Telefone", "Sexo" and "Aniversário" on 2026-10-15 (LGPD art. 6
III). The app selects `profiles` by named columns, so it never reads `phone`,
`sex` or `birthday_label`, and a profile save no longer sends them at all
(`ProfileUpsertRow`, locked by
`RemoteDecodingTests.testSavingAProfileNeverSendsThePhoneSexOrBirthday`):
Heitor's decision of 2026-10-15 leaves the columns unused rather than blanked
on save. What an earlier build stored stays until the operator's planned
one-off server statement clears it, like the notes above, and another adult of
the house can still read it through the API until then; dropping the columns
is a later migration. A profile cached by an earlier build still opens
(`PrivateLocalDataStoreTests.testAProfileCachedByAnOlderBuildOpensWithoutItsPhoneSexOrBirthday`).

**`Route` now has four cases and all of them are reachable** — `task`, `member`,
`workload`, `memories`. This was fixed in the rebrand: `RouterPath.navigate(to:)`
used to have zero call sites, so `task.createdBy` was captured on every task and
rendered nowhere, and every member tap landed in an edit form even for a viewer
who cannot edit. `TaskDetailView` and `MemberDetailView` are the live screens;
`TaskDetailCard` and `MemberDetailContent` are gone.

**Custom task sections are no longer reachable from the UI.** `TaskSection`
survives in the model and on the wire, but Tarefas groups by *category*, per board
`T1`. This is a deliberate feature removal recorded in
`docs/rebrand-implementation.md` §2.

**`enqueueRemoteMutation` silently no-ops** when there is no active user, no
backend, a DEBUG account, or no active home. The mutation persists locally and
never syncs, with no error surfaced.

**`restoreSession()` signs out only on an `AuthError`.** Any other failure
(a dropped refresh, a timeout, `ensure_current_profile` unreachable) returns
`.unreachable(user)`, which keeps the signed-in user and lets the home context
decide access. Until 2026-09-08 every thrown error returned `.signedOut`, so a
network blip on the foreground transition bounced people to `LoginView` with an
intact Keychain session. The same rule holds for joining (`inviteRefused` is the
only error that may call an invite dead) and for reminders (an `.unavailable`
membership never re-syncs notifications).

**Signing out takes the household off the phone (since 2026-10-05).**
`AppRootView` calls `AppStore.clearHouseholdCopy` and
`ProfileStore.clearLocalData` for the account that just left, removing the
cached house, the consent cache, the profile and the photo; the server holds
them for the next sign-in. A minor's usage ledger and the last age reading
stay, so signing out and in never resets a daily limit or re-runs the age step,
and the tutorial flag stays. Account deletion still clears everything. The
clearing first invalidates the context, so a late reply cannot write the house
back, and it removes the reminders already shown; "Sair da casa" does the same
for the house it leaves. So the adult's "Sair da conta" in Ajustes asks first
("Sair da conta?" / "Para entrar de novo, use sua conta Apple."), armed by
`Haptics.warning()`; the exits on the age check, the gates, house setup and the
pending, decision and unavailable screens hold no house and answer with
`selection()` (since 2026-10-15). A failed sign-out reads "Não deu para sair da
conta agora. Tente de novo." (`AuthFlowError.signOutFailed`), never the sign-in
line.

**iOS is asked for alerts in context, once, and never at launch** (since
2026-10-15). `AppStore` asks only after it has read iOS's own status
(`refreshNotificationAuthorizationStatus`, which `AppRootView` runs before the
shell mounts): right after this phone confirms a dated task or reminder (a
proposal, a new task, an edit or a planted semente), and on a minor's first
visit to their tasks while the guardian keeps alerts on; never someone who
switched "Avisos" off in Ajustes. No line precedes the system prompt (rubric
K5). While iOS is undetermined or denied, `NotificationPermissionChip` ("Ativar
avisos" / "Avisos bloqueados") sits in the task editor and under a dated pending
proposal card; under Hoje's header only "Ativar avisos" shows, while iOS has not
been asked and "Avisos" is on, so a refusal never becomes a standing chip on the
main screen. A minor's "Avisos" value and the
daily-limit line read the guardian's switch and iOS's answer together
(`AppStore.minorAlertsValue`). Locked by
`AppStoreAuthorizationTests.testConfirmingADatedProposalAsksIOSForAlertsOnceItsAnswerHasBeenRead`,
`…testSomeoneIOSAlreadyAnsweredIsNeverAskedBeforeThatAnswerIsRead`,
`…testAManualDatedTaskAsksOnceAndNeverAsksSomeoneWhoSwitchedAlertsOff`,
`…testAMinorsPhoneIsAskedOnItsHomeOnlyWhileTheGuardianKeepsAlertsOn` and
`…testAMinorsAvisosValueSaysWhatThisIPhoneWillActuallyDo`.

**Notification scheduling is capped at 60 requests globally**, with recurring
tasks expanded 12 occurrences deep. Since 2026-10-05 every task's next alert is
booked first and later repeats fill what is left by soonest delivery, so daily
chores can no longer push a one-off task out; a home with more than 60 open
dated tasks still loses the latest ones. Booked reminders never end in silence:
whenever a repeating task or the budget leaves alerts unbooked, one slot goes to
a notice a minute after the last alert booked before the first gap (the end of
the soonest repeating task's 12, or the first alert the budget left out), "Abra
a Nina para receber os próximos lembretes." (`HomeNotificationKind.horizon`, no
task id, no buttons), because nothing re-arms the schedule without the app. A
minor's phone never gets it. **First alerts and follow-up nudges are budgeted separately**:
alerts fill the 60 first, nudges take only the remainder, so a repeat of
something the phone already showed can never evict the one time another task is
announced. One nudge per task, not per occurrence, and a task whose first alert
was dropped gets none. A `.high`/`.urgent` task therefore costs up to two
requests — a household of mostly urgent tasks reaches the ceiling with roughly
half as many. Quiet hours **silence** rather than move: `content.sound = nil`
and `interruptionLevel = .passive`, delivery time unchanged, because the app must
never show one time and deliver another. Since 2026-10-05 every
`UNCalendarNotificationTrigger` carries the calendar's time zone, so an alert
fires at the instant the card shows even after a trip, and its only `userInfo`
is `task_id` and `due_at` (the occurrence's instant, as seconds):
`NinaNotificationDelegate` shows a reminder that fires while the app is open and
routes a tap through `TaskNotificationRoute` to that task in Hoje (a task gone
by then opens nothing). An adult's reminder carries buttons (`ReminderActionSet`):
"Marcar como feita" or "Feita por hoje", plus "Adiar 1 hora" only when it fires
at or after the due hour. **Every button opens the app first** (`.foreground`),
so nothing is written from a locked phone or in the background, where the home
context may not be loaded; a completion lands on Hoje under the undo toast.
`ReminderRoute.completes` never rolls a repeating task past the occurrence the
reminder announced, `toggleTask(_:through:)` closes that occurrence even when an
earlier one was missed, and `snoozeTarget` never pulls a task earlier than its
card. A minor's reminder carries no buttons. While a child's list covers the
screen, an adult's reminder goes silently to Notification Center and any button
pressed waits until the hold ends, so nothing changes in the house from a
child's hands. **The body never contains `task.subtitle`** —
it used to, which put a photographed boleto's reading on the lock screen verbatim.
Nina speaks a sentence and names only who is holding the task;
`NotificationTargetingTests.testTheTaskDetailNeverReachesTheLockScreen` fails if
the detail ever returns. There is still no preview-redaction control, so the
*title* the person typed does reach the lock screen: never claim otherwise in copy.

**`dueLabel` and `dueAt` are read by one rule on three layers.**
`resolveDueInstant` (`supabase/functions/_shared/nina-due-date.ts`) and
`AppStore.inferredDueAt` implement the same pt-BR reader: "dia 20", "20/10",
"20 de outubro", "hoje", "amanhã", "depois de amanhã", "daqui N dias", weekday
names with or without "-feira", accents, "que vem" or "próxima", the ordinal
weekdays "2ª" to "6ª" with or without "feira", "14h", "14h30", "14:30", "às 9",
"meio-dia", "meio-dia e meia", "2 da tarde", "8h30 da noite", and their
combinations. Dates are read before times, so "dia 10 de manhã" is the 10th at
09:00 and never 10 in the morning. Both run the same `sharedDueTable` (Deno
`nina-due-date.test.ts`, XCTest `TaskAgendaTests`), and a Deno test fails when
the Swift copy of the table drifts from the TypeScript one. A day with no time is booked at 09:00 — `ninaDefaultDueHour`,
`AppStore.defaultDueHour` and the prompt, each pinned by a test. "Dia N" and a
weekday mean the next occurrence still ahead; "dia 31" skips months without a
31st. **The reader refuses rather than guesses**: a duration ("a cada 8 horas",
"8/8h", "daqui 2 horas"), two different dates or times ("sexta ou sábado"), an
alternative or a range ("dia 5 ou 6", "entre 14 e 16h", "das 10 às 12h", "14h
30"), a bare "às 1" to "às 7" (as often 17h as 5h), a part of the day with no
clock time ("hoje à noite", "dia 20 de noite"), a word it cannot place ("ontem",
"semana que vem", "Sex", a stray "às 10 de pegar", "a 4ª reunião") or an ordinal
("segunda via", "2ª via", "sexta série", "1/2 comprimido") yields `nil`, and the
task keeps its label with no notification — the card says "· sem lembrete"
before the tap. Nina herself may still date a phrase the readers refuse, such
as "às 5", which the prompt asks her to compute; the card shows her date before
the tap, and no layer moves it. The one intended difference
between layers: "hoje", or today's date written with its month ("26/09", "26 de
setembro"), with no time once 09:00 has passed is `null` on the server, which
cannot know when the person will confirm, and now + 5 minutes on the phone,
evaluated at confirmation. "Dia 26" and a weekday said that day go to the next
occurrence on both layers. The phone anchors an untouched relative label at
confirmation time, not when it was said, so
"amanhã" on a proposal left pending for days means the new tomorrow; the card
shows the resolved date before the tap. The server resolves in
`America/Sao_Paulo` and the phone in the device's zone: they agree on Brasília
time and differ by 1–2 hours in Manaus, Acre and Noronha until the chat request
carries the device's zone. The message fallback can date a proposal from a day
said about something else ("Comprei presente dia 10, me lembre de embrulhar"
books the 10th); the card shows it before confirmation, and a message naming two
different days dates nothing.

**The Supabase MCP `apply_migration` records its own version.** It writes a
14-digit timestamp to `supabase_migrations.schema_migrations`, not the
filename's `YYYYMMDDNNNN`, and `supabase db push` then refuses the history
until it is repaired. After applying through it, set that row's `version` to
the filename's number, as was done for `202609260001`.

**`deno task db:test` runs against the database as it stands, not against the
migrations.** It never applies anything. Editing a migration and re-running only
`db:test` tests the previous schema and passes for the wrong reason —
`deno task db:reset` first. Editing a pgTAP file alone needs no reset. Also note
`supabase start` writes an untracked `supabase/.branches/`; it is ignored, and
must stay ignored, because another session's `git add -A` would otherwise commit
local machine state.

**iCloud leaves "… 2" copies in the working tree.** The repo lives in
`~/Documents`, which iCloud syncs, and it drops conflict copies such as
`202609290001_age_assurance 2.sql` or `index 2.ts` next to the originals.
`.gitignore` hides them (`*\ 2.*`), so `git status` stays clean, but the
Supabase CLI does not read `.gitignore`: `db push` would take a
`NNNN_name 2.sql` as a second migration with the same version (it sorts before
the original), and `functions deploy` could upload stale copies. Push
migrations and deploy functions from a clean export
(`git archive HEAD | tar -x -C <dir>`, then run the CLI there), as the
2026-09-29 release did. The local gate reads the same folders: on 2026-10-14
`deno task db:reset` in the working tree applied
`202609290001_age_assurance 2.sql` and stopped on a duplicate key in
`schema_migrations_pkey`, and `db:test` would also run the stale
`supabase/tests/database/* 2.sql` copies. While copies exist, reset from an
export with the uncommitted files laid over it (`git ls-files -m -o
--exclude-standard`, which leaves out the ignored copies); the export keeps
`project_id`, so it drives the same local stack. Then test from the working
tree with the files named, a glob the copies do not match:

```sh
npx --yes supabase@2.110.0 db lint --local --fail-on error && npx --yes supabase@2.110.0 test db --local supabase/tests/database/*.test.sql
```

Never run `test db` from an export outside the home folder (`/tmp`, the
scratchpad): colima mounts only the home folder into its VM, so the test
container sees an empty folder and reports `Files=0` and `Result: NOTESTS`
with exit 0, a pass that tested nothing (seen 2026-10-14).

**`deno.json` enumerates individual files, not directories.** A new
`web/src/*.ts` or `_shared/*.ts` module is neither formatted, linted, nor
type-checked until you add it. Likewise `deno task test` globs only
`_shared/*.test.ts`, `web/tests/*.test.ts`, and `Tools/*.test.ts` — a test
placed elsewhere never runs and CI stays green.

**`deno.lock` is `frozen: true`** with `nodeModulesDir: "none"`; adding any
import without regenerating the lockfile fails the edge-functions job before any
test runs.

**Preflight exits 0 with warnings.** Omitting `--online` or `--ios-artifact`
produces warnings, not failures. "0 failure(s)" does not mean the gate passed —
check the warning count. Passing a `.app` instead of an `.xcarchive` downgrades
`artifact.archive-signing` to a warning, so an unsigned build can produce a
zero-failure run.

**`Deno.env.toObject()` is spread after the parsed `--env-file`** in the
preflight — a stale exported shell variable silently overrides the file.

**The placeholder regex includes the literal word `example`**, so a genuine
production value containing "example" is rejected as a placeholder.

**The credential scanner reads tracked files only.** `repository.secret-content`
walks `git ls-files`, so a secret-shaped literal in an untracked file is
invisible until you commit it. When adding a deliberately secret-shaped test
fixture, give it a body containing `example` / `replace` so the scanner's
placeholder heuristic classifies it correctly — that is the existing convention
(`sb_secret_replace_with_a_dedicated_worker_key` in `config/production.env.example`).
Never obfuscate a fixture to dodge the scan.

**A function that answers before reading the whole upload never delivers that
answer.** Supabase holds the connection until its idle timeout and returns an
empty 503 from the gateway. Proven 2026-09-28: a 1 MiB body to
`premium-subscription-sync` and a 13 MiB body to nina-chat v13 both hung, while
an 11 MiB body read to its end answered in 1.6 s. So `readNinaChatRequest`
drains an oversize body up to `maxDrainedRequestBytes` (32 MiB), keeping none of
it, and only then answers 413. The App Store functions and `delete-account`
still answer early; nothing legitimate sends them an oversize body, so an
oversize request there gets the empty 503 and nothing else.

**`app-store-server-notifications` is publicly reachable** with no shared secret
or IP allowlist — Apple's JWS chain is its only authentication. Sound, but every
unverifiable POST costs a certificate-chain verification. Apple root certs are
downloaded from apple.com at cold start unless `APPLE_ROOT_CA_PEMS` is set.
**Never reintroduce `SignedDataVerifier` from Apple's library on this path**: it
needs `node:crypto` X.509 support the edge runtime does not have, and the
failure looks like "every receipt is invalid" with an empty error. The local
reproduction is `supabase functions serve` with a throwaway function, which
runs the same runtime container as production.

**`nina_ai_budget_months` is one global row per (month, purpose), not per
family.** One heavy household can exhaust the US$20 cap and every other user
starts getting 429 `monthly_budget_reached`.

**Moderation runs *after* `begin_nina_chat_run`**, so a flagged message still
consumes quota. This ordering is deliberate and asserted by a test — do not
"optimize" it. It reads the *pseudonymized* text, so the moderation provider
never sees a minor's name either. Note that document attachments are never
moderated; only text and images are — one more reason attachments stay off for
the all-ages launch (`NINA_ATTACHMENTS_ENABLED = NO`).

**Production Auth must have one provider on: Apple.** Email is still on until
the runbook §2 dashboard step is done (§13). Email login existed until
2026-09-26 and was fragile: on 2026-09-09 the email provider was found off, the
SMTP password was a deleted Resend key, and `rate_limit_email_sent` was 2 per
hour for the whole project. None of that is on a sign-in path any more: the app
never asks Auth for an OTP, a magic link or an email change. What matters is the
provider list: Apple on, Email off (`docs/production-launch-runbook.md` §2). A
TestFlight build of 7 or earlier still shows "Entrar com email"; with Email off
an address that has an account gets the generic "Não foi possível entrar agora.
Tente de novo.", a new address gets that build's no-account line, no code is
sent either way, and its Apple button keeps working. Build 7 also carries a
hidden "Continuar com o Google" row that appears if Google is ever enabled, so
keep Google off; `deployment.sign-in-providers` fails the online preflight if
it is on. The local stack keeps `[auth.email]` because the AI eval signs in
through an admin magic link. Since build 11 Apple's provider must also have
"Allow users without an email" (`email_optional`) on: the sign-in never asks
Apple for the email (build 12 asks for the name alone), so a new Apple ID's
identity token carries no
email, and with the switch off GoTrue refuses the account and every new person
reads "Não foi possível entrar agora. Tente de novo." `supabase/config.toml`
covers only the local stack; production is the dashboard (runbook §2).

**'Família' is the server's word for no name yet.** `auth_user_display_name`
falls back to `'Família'` when an account has no metadata name and no email,
which is every account made since build 11 until the person is named, and
`ProfileNaming` reads that word (with "Você" and an empty name) as a name
nobody chose. Change both together; the Deno "the app reads the server's
fallback name as no name" pins them. A `display_name_hint` would not change
this for long: a hinted name is auth-owned, so the next
`ensure_current_profile(null)` turns it back into `'Família'`, and only
`chooseDisplayName` (source `'user'`) makes a name stick, which is why the
sign-in sends none. The same re-derivation keeps the full name for an account
made with builds up to 10: those builds wrote the formatted full name Apple
shared to `display_name` and `full_name` in Auth user metadata, so its
auth-owned profile name, and the `family_members.name` a house copied from it,
is the full name until the person renames in Perfil. An adult
who already sits in a house as "Família" (a pre-build-11 account whose welcome
reading was unavailable) keeps that frozen `family_members.name` until a rename
in Perfil reaches the profile; the house row itself never follows.

**An unsigned simulator build cannot sign in.** With `CODE_SIGNING_ALLOWED=NO`
the build carries no entitlements, Sign in with Apple included, so the Apple
request fails at once (`AuthorizationError` 1000) with the generic "Não foi
possível entrar agora". Even a successful sign-in could not persist: every
`SecItem` call fails with `-34018`, which the Supabase SDK logs as "Failed to
store session" only through its optional logger. For any simulator check that
signs in, build without that flag (ad-hoc signing is automatic). A UI check against production
now signs in with Apple, which needs an Apple Account signed in to the
simulator; the throwaway-email OTP route is gone, and the DEBUG test accounts
reach only the local home. Also: one simulator at a time — a second session
driving the same device produces phantom taps, and three booted devices wedged
CoreSimulator on 2026-09-09.

**App Attest and Declared Age Range do not run on the Simulator.** An account
signed in on the Simulator against a real backend never records an age, so it
stays unknown and lands on `minorRoot`.
Against a loopback stack a DEBUG build falls back to the `insecure-local` key
id, which only an `age-signal` running with `NINA_APP_ATTEST_MODE=insecure-local`
on a loopback `SUPABASE_URL` accepts; against production, mark the account with
`private.operator_set_age_status(…, 'adult', null, true, 'testflight')` in the
SQL editor. Real age answers come only from a device: Apple's age-assurance
sandbox on iOS 26.4+ (Settings › Developer › Sandbox Apple Account) and real
Brazilian accounts. The embedded Apple App Attestation Root CA in
`_shared/app-attest.ts` is byte-identical to Apple's published
`Apple_App_Attestation_Root_CA.pem` (compared 2026-10-04), and two real Apple
attestations chain to it (§7); still prove one real-device assertion
(the digest is hashed twice, as ECDSA-P256-SHA256 over
`SHA256(authenticatorData ‖ clientDataHash)`) before launch.

**iOS 26.4 is the floor everywhere, CI included.** Every build configuration
sets `IPHONEOS_DEPLOYMENT_TARGET = 26.4` (`repository.deployment-target-minimum`,
`artifact.deployment-target-minimum`), because `requiredRegulatoryFeatures`
exists only from 26.4. CI's iOS job moved from `macos-15` to `macos-26` on
2026-09-29 and now fails fast, with a plain message, when the newest stable
Xcode ships an iOS SDK below 26.4 or no iPhone simulator on iOS 26.4+ exists;
the first push after that change is the first proof the hosted image has both.

**The age migrations turn every existing account unknown until it attests.**
After `202609290001`–`…0008`, a person with no `account_age_status` row reads
the minimized minor shape, cannot create a house or chat, and every earlier AI
consent is withdrawn (`policy_changed`). A build without the age step (TestFlight
9 and earlier) cannot attest, cannot grant a consent (the two-argument call now
lacks the transfer consent), and cannot approve a minor (the declaration is
missing), so expire those builds in App Store Connect before the migrations run.
The reverse is just as bad: the new app reads a home context without
`viewer_kind` as a minor's, so shipping the build before the migrations shows
every adult the minor screen.

**Realtime stays silent for minors by design.** Every household table is
adult-only under RLS, so a minor's device receives no row events; its list
refreshes on foreground, after its own writes and on pull. Do not "fix" it with
a grant.

**A minor's daily limit is counted on the device.** Foreground seconds come from
`scenePhase` and sync through `record_minor_usage` when the app goes to the
background, so time is lost if the app is killed first, and the server value is
re-read on each foreground. iOS Screen Time is the real lock; the Terms (§4A)
and the guardian's "Sem limite" line say so.

**An owner who becomes a minor keeps `household_role 'adult'` and
`permission_role 'owner'` on the row** (the minor-permission CHECK forbids a
minor owner) but loses every power: `can_manage_family`, the RLS helpers and
`begin_nina_chat_run` all read age status, not the row. An admin who becomes a
minor is demoted and re-derived. **`prepare_account_deletion` deletes a house at
once when no adult is left to inherit it**, not after the 30 days the spec
suggested, and an unattested legacy member (unknown) cannot inherit either, so
on TestFlight a house can disappear when its only confirmed adult deletes the
account before the other adult has attested.

**Five inline `npm:` imports carry `// deno-lint-ignore no-import-prefix`**
(`@noble/curves` and `@peculiar/x509` in `_shared/app-attest.ts` and in its
test, and `age-signal/index.ts`), so `age-signal` needs no import map.
`deno.lock` pins `@noble/curves@2.4.0` and its one dependency
`@noble/hashes@2.4.0`, added 2026-10-04 for the chain check (§7).
`delete-account` still imports by bare specifier through
`import_map = "../deno.json"` (§7).

**The report and privacy mailboxes are constants in the app.**
`NinaLegalLinks.privacyEmail` and `.reportEmail` are both
`privacidade@ninai.app`; the website reads `PUBLIC_NINA_REPORT_CONTACT_EMAIL`,
which falls back to the privacy address. A dedicated report mailbox (D2) means
changing both, or the app and `/denuncia/` name different addresses.

**`Tools/run_nina_ai_eval.mjs local` is the only way the eval runs.** It needs
the local stack plus `functions serve`, refuses any API URL that is not
loopback, seeds its fixtures with SQL, signs in through an admin magic link, and
changes no Auth setting. Every other argument, a project ref included, is
refused before anything runs: the remote path it had until 2026-09-23 turned on
email auth, created real Auth users, and seeded then deleted a family in the
project it named, and it was removed rather than repaired. It still calls OpenAI
with the key in `supabase/.env.local`, so each run costs real money, and it
writes to a temp directory, never over the committed report. That file also
needs a `NINA_SAFETY_ID_SALT` of at least 32 characters, or every turn answers
`503 service_not_configured`. A refusal is held to the same reply checks as an
answer (`reply_must_include` / `reply_must_exclude` read the refusal's reply
too). **Never point an eval at production.**

---

## 13. Known gaps and launch blockers

Honest state as of 2026-08-10, with later dated entries. These are facts about
the project, not bugs to fix unprompted.

- **Nina for all ages is live on the server since 2026-09-29.** The eight
  `202609290001`–`…0008` migrations, `age-signal`, the changes to the other five
  functions, the iOS age step, minor experience, guardian sheets and consent v2,
  and the web Terms, Privacy, `/familias/` and `/denuncia/` pass every local gate
  (Deno 314 tests, pgTAP 657, XCTest 409, repository preflight, Debug and
  Release builds, `astro check`). The local eval on the 38-case fixture is below
  (§13, the AI eval entry). The production day (`docs/production-launch-runbook.md`
  §3) ran on 2026-09-29: TestFlight builds ≤9 expired, the five secrets set,
  the eight migrations applied by `db push` (versions match the filenames), the
  six functions deployed, `legacy_profile_deadline` set to 2026-10-29, and the
  online preflight with the build-10 archive left only the expected
  `deployment.legal-launch-identity` failure. No tester account was marked with
  `operator_set_age_status` until 2026-10-06, when Heitor's own account (a
  self-declared adult after build 11's age step) was marked `testflight` so
  he can chat. A later signal from his iPhone replaced that mark before
  migration `202610140001` existed (on 2026-10-14 production logs read
  `self_declared` on every retry), so after D3 he chats as a self-declared
  adult, and acting for a minor needs the mark again
  (`private.operator_set_age_status('<id>', 'adult', null, true, 'testflight')`),
  which his phone's adult signals leave in place since `202610140001` was
  applied the same day. Every other reading in `private.age_assurance_distribution()` shows
  how a real iPhone came back. Build
  10 reaches the external group only after Beta App Review. Still open on a device, since
  the Simulator runs neither: an Apple-confirmed adult, a self-declared adult, a
  16–17 and a 13–15 Family Sharing child, an under-13, Sign in with Apple with no
  scopes, a decline and a later share, a guardian approval and a guardian
  deletion end to end.
- **Build 11 (2026-10-04) is Apple first, and its sign-in is unproven on a
  device.** Heitor's play test of build 10 decided four changes: the welcome is
  one black Apple button with no scope for anyone (the age is read after
  sign-in, an adult types a first name where the house first needs it), the
  rating mark only on the welcome and the startup screen, a centred wait with a
  round disc, and typed account-deletion failures with a mail way-out.
  `CURRENT_PROJECT_VERSION` was 11. Heitor turned on Apple's "Allow users without
  an email" in production Auth on 2026-10-05 (§12); still prove the no-scope
  sign-in with a brand-new
  Apple ID (or one that removed Nina under Sign in with Apple) on a device,
  landing on "Antes, sua faixa de idade.", because every new account now takes
  that path; and Heitor accepts handling a deletion request mailed to
  privacidade@ninai.app (`docs/production-launch-runbook.md` §2, "Deletion
  requests by mail"), where the mail's reference only finds the account and the
  sender proves control by typing a mailed one-time code as their Perfil name.
  App Review Guideline 4.0 has refused apps that ask for a name after Sign in
  with Apple, and build 11's typed field for every new adult was exactly that;
  build 12 answers it (next entry). The "Não deu para apagar a conta agora"
  Heitor saw on build 10 came from the pre-release delete-account (deployment
  version 3 in the function logs; three build-10 attempts on 2026-09-29
  between 10:58 and 16:51 UTC), which accepted only `{"confirmation":"delete"}`
  and refused the Apple-code body with 400 `confirmation_required`; v7
  (2026-09-29 19:30 UTC, the HEAD contract) accepts all three bodies. The logs
  read on 2026-10-06 show no app request to v7 yet, so one real deletion
  against v7 on a device still closes it.
- **Build 12 (2026-10-05) asks Apple for the name alone.** Heitor's decision,
  for the Guideline 4.0 risk above: `requestedScopes = [.fullName]` for every
  account, never `.email`; only the given name is kept, on the phone until the
  person is named, and saved as the person's chosen name before the house
  copies it, so an adult who shares a name never sees "Seu primeiro nome"; the
  typed field stays only as the fallback when Apple gives no given name (a
  later authorization, or a name blanked in Apple's sheet). Heitor's brief said
  to send the given name as `ensure_current_profile`'s `display_name_hint`; a
  review found that the hint wrote a minor's name to `profiles` and the
  protected profile cache before the age was known, while
  `get_current_home_context` re-derived it to `'Família'` on the next load
  anyway, so the sign-in sends no hint and the name waits on the device (§4,
  "A house member is named by the person"). A minor, or anyone whose age Apple
  has not shared, still confirms a first name beside the invite, prefilled with
  Apple's given name, and no family name is stored for any account made since.
  Accounts made before build 11 keep what builds ≤10 wrote when Apple shared
  it: the full name in Auth user metadata (`full_name` and `display_name` in
  `raw_user_meta_data`), which is also their profile name and the name their
  house copied (§12, "'Família' is the server's word"), and the email; nothing
  rewrites or removes those. `CURRENT_PROJECT_VERSION` was 12. The App Review
  notes carry the Sign in with Apple paragraph in
  `docs/production-launch-runbook.md` §6 word for word. The email switch is on
  in production Auth since 2026-10-05 (Heitor, §12); the release blockers left
  are on a device: a brand-new Apple ID (or one that removed Nina under Sign in with
  Apple) that shares its name reaches house setup with no name field, also
  after closing the app between Apple's sheet and the house, and the house
  names it by the given name alone; one that blanks the name sees the field.
  Build 10 asks adults for the email; the website privacy page names the
  builds, so it stays true while build 10 is still installed.
- **Build 17 (2026-10-18) colours the priority flags.** Archived from the
  sources tagged `testflight-1.0-17` with `CURRENT_PROJECT_VERSION` 17; the
  online production preflight against the archive read 0 failures and 0
  warnings. Its one change: Urgente is a red flag and Alta a yellow one, on
  the rows and the task's detail (§5, "Priority is a coloured flag"). Heitor
  chose to keep the yellow flag's edge on 2026-10-18.
- **Build 18 (2026-10-18) carries the 14 rating mark.** Archived from the
  sources tagged `testflight-1.0-18` with `CURRENT_PROJECT_VERSION` 18; the
  online production preflight against the archive read 0 failures and 0
  warnings. Its one change is the orange "14" on the welcome and the startup
  screen (§13, "The rating is 14"). Heitor tested it on 2026-10-18.
- **Build 20 (2026-10-19) centres the gates' message.** Archived from the
  sources tagged `testflight-1.0-20` with `CURRENT_PROJECT_VERSION` 20; the
  online production preflight against the archive read 0 failures and 0
  warnings. Its one change: the Nina mark, the headline and the line of the
  Terms and age gates sit centred, like the welcome. Build 20 is the release
  candidate Heitor tests before any test data is deleted.
- **Build 19 (2026-10-19) is Heitor's last fixes.** Archived from the sources
  tagged `testflight-1.0-19` with `CURRENT_PROJECT_VERSION` 19; the online
  production preflight against the archive read 0 failures and 0 warnings.
  The tinted priority rows
  (§5, "Priority is a tinted row"), the shopping quantity with −1, +1 and +10
  steps (`ShoppingAmount`, `ShoppingAmountField`; a step moves only the
  leading whole number, so a unit Nina or a person wrote is never lost), the
  gates rebuilt on LoginView's skeleton (`GateLayout`: the message above, the
  Terms card, the commit and the exits at the foot), and no rating mark in
  the app (§5).
- **Build 16 (2026-10-15) adds the priority flag to build 15.** Archived
  from the sources tagged `testflight-1.0-16` with `CURRENT_PROJECT_VERSION`
  16; the online production preflight against the archive read 0 failures
  and 0 warnings. Its one change is the ink flag on task rows, the last fix
  Heitor listed in his notes. He tested it on 2026-10-18: everything worked,
  and the flags became yellow and red in build 17.
- **Build 15 (2026-10-15) is Heitor's two asks after testing build 14.**
  Archived from the sources tagged `testflight-1.0-15` with
  `CURRENT_PROJECT_VERSION` 15, after migration `202610150001` was applied
  and the Terms of 15 October went live; the online production preflight
  against the archive read 0 failures and 0 warnings. It carries "Apagar a
  casa" for the titular (Ajustes › Casa, and from "Sair da casa" when nobody
  else can take the house), join requests that reach Casa live, and pull to
  refresh on Casa, Hoje and Tarefas. Heitor's play test of build 14 found
  everything else working, invites included.
- **Build 14 (2026-10-15) is the launch-audit polish.** Archived from the
  sources tagged `testflight-1.0-14` with `CURRENT_PROJECT_VERSION` 14; the
  online production preflight against the archive read 0 failures and 0
  warnings. It carries the empty-space pass (fitted sheets, commits after
  their fields, no wrapped labels) and batches 1-3 of the 2026-10-15 launch
  plan: Perfil without phone, sex or birthday; alerts asked after the first
  dated confirmation and on a minor's home; Release without `MockNinaEngine`
  or `PreviewData`; refusals that keep the person's words and add no line in
  Nina's name; the weekly-summary, portrait (adults only) and child-gate
  lines. Heitor tests it before any test data is deleted (his order of
  2026-10-15).
- **Build 13 (2026-10-14) carries the tour and everything since build 12.**
  Archived from the sources tagged `testflight-1.0-13` with
  `CURRENT_PROJECT_VERSION` 13; the online production preflight against the
  archive read 0 failures and 0 warnings. It brings the tour of the four tabs
  (`OnboardingTutorialView`, §5), "Passar a casa", "Titular" and "Sair da
  casa" (migrations `202610050001` and `…0003`), "50 mensagens por dia" in
  the chat ceiling and the paywall (`…0004`), the Nina tab's mark, the phone
  that formats as it is typed, the pet species menu without breed, "A Apple
  manteve a mesma resposta." after a retry that changed nothing, the FAQ
  "Quem pode conversar com a Nina?" and the parental-controls gates (D3).
  Heitor's play test of build 12 (2026-10-13) proved on a device what build
  12 still lacked: an account deletion against `delete-account` v7 (200),
  App Attest registration and assertion on a real iPhone, and a brand-new
  account named by Apple's given name alone, with no email and no name in
  Auth. An account that finished build 12's rehearsal keeps its tutorial
  flag, so it meets the tour only through Ajustes › "Rever a demonstração".
- **Migration `202609290009` is applied to production (2026-09-30).** It
  revokes `can_manage_family`, `is_family_member` and `is_family_creator` from
  every API role and makes `shares_family_with` answer only about the caller.
  Production had refused the age question since `…0004`; what `…0009` closed
  was membership: a signed-in account that knew a house id and a user id could
  ask whether that person was in the house or created it, and whether any two
  user ids shared a house. It went through the Supabase MCP `apply_migration`
  with the file's body, and its `schema_migrations` row was set to
  `202609290009` (§12). The same day the catalog was read back: no API role
  executes the three predicates, the 13 SECURITY DEFINER callers are owned by
  `postgres` and still execute them, a signed-in read of `profiles` and
  `families` evaluates its policies without a permission error, and both
  function grant maps in `rls_policies.test.sql` (47 `authenticated`, 27
  `service_role`) equal production's.
- **Migration `202610050001` (`leave_family`) is applied to production
  (2026-10-05).** Additive: one SECURITY DEFINER function, executable by
  `authenticated` alone (read back after the apply: anon and service_role
  false). It went through the Supabase MCP `apply_migration`, and its
  `schema_migrations` row was set to `202610050001` (§12). The authenticated
  function grant map became 48 names. The "Sair da casa" row that calls it
  reaches people with the first build after 11.
- **Migration `202610050002` (foreign-key indexes) is applied to production
  (2026-10-05).** It indexes the 33 foreign keys the production advisor listed
  and fixes `set_updated_at`'s search path; `foreign_key_indexes.test.sql`
  fails if any foreign key in `public` or `private` lacks a leading index. It
  went through the Supabase MCP `apply_migration`, its version row was set to
  `202610050002` (§12), and the same canary query read 0 on production.
- **Migration `202610050004` (Premium chat limit by the day) is applied to
  production (2026-10-05).** It copies `begin_nina_chat_run` from
  `202609290006` with one change: a covered adult's claim is 50 per 86,400
  seconds instead of 30 per 3,600. Production's function body matched the
  local pre-change body by MD5 before the apply and the post-change body
  after it; grants read back authenticated only. It went through the Supabase
  MCP `apply_migration` and its version row was set to `202610050004` (§12).
  It went live before the push that publishes "50 por dia" on `/suporte/` and
  the landing, so the site never promised more than the server keeps. Build
  12 still says "30 mensagens por hora" in the chat's ceiling notice and the
  paywall until people update to build 13.
- **Migration `202610050003` (owner title and handover) is applied to
  production (2026-10-05, Heitor's "go database").** It adds
  `private.family_ownership_offers` and the offer, accept and withdraw RPCs,
  adds `ownership_offer` to `get_current_home_context` (copied verbatim from
  `202609290005` otherwise), and clears the `'Criador'` relationship.
  Production's `get_current_home_context` and `create_family(text, text)`
  bodies matched the pre-change bodies by MD5 before the apply, and all seven
  new or redefined bodies matched the local ones after it; the read-back
  showed 0 `'Criador'` rows, the offers table with RLS on and no API grant,
  51 functions `authenticated` executes (the grant map in
  `rls_policies.test.sql`), 0 unindexed foreign keys, and the version row set
  to `202610050003` (§12). Build 12 ignores the new key; "Passar a casa"
  reaches people with build 13.
- **Migration `202610140001` (the operator's mark outlives the phone) is
  applied to production (2026-10-14, Heitor's "go database").** It copies
  `private.store_age_status` from `202609290002` with one block: while the
  ratchet runs, an adult signal over an adult whose assurance is `operator`
  keeps `operator` (parental controls still follow the device, and a minor or
  declined signal replaces the mark), so a tester's or an age contest's mark
  survives the person's own retries (§4, "Age is a server-held band").
  Production's `md5(prosrc)` for
  `private.store_age_status(uuid, text, text, text, boolean, boolean)` read
  `9f55c4060cd066e52d4657399e7286ee` (the `202609290002` body) before the
  apply and `f1efbacfcf913fb82947e7e9412aef8f` after it, the local body; the
  ACL reads `{postgres=X/postgres}` and neither `authenticated` nor
  `service_role` executes it. It went through the Supabase MCP
  `apply_migration`, and its `schema_migrations` row was set to
  `202610140001` (§12). It needs no new build.
- **Migration `202610150001` (deleting a house) is applied to production
  (2026-10-15, Heitor's "go database").** Heitor asked on 2026-10-15, after build 14, that a titular alone
  (or any titular) could delete the house instead of being told to pass it
  first. It adds `family_access_decisions.house_deleted`, the private
  `delete_household` and `settle_household_ai_runs`, and the client RPC
  `delete_family(uuid, text)` (the authenticated grant map in
  `rls_policies.test.sql` becomes 52 names), and redefines
  `get_family_access_decision()` (adds `house_deleted`),
  `prepare_account_deletion(uuid)` (its two house deletions now call
  `delete_household`, and it clears the report copies on the person's own
  reports; otherwise the `202609290004` body) and
  `private.preserve_child_safety_account(uuid)` (a second copy merges into the
  first instead of `on conflict do nothing`; otherwise the `202609290008`
  body). On `nina_ai_consents` it drops `family_id`'s not-null, makes
  `nina_ai_consents_family_id_fkey` `on delete set null` (it was `cascade`)
  and adds `'house_deleted'` to `nina_ai_consents_revoke_reason_check`.
  Read-only checks on 2026-10-15: production's `md5(prosrc)` was
  `9dff4d97109e91ac13123982f9c59398` for `get_family_access_decision()` (the
  `202608090007` body), `d61cf299c129e8a081c513112494cab1` for
  `prepare_account_deletion(uuid)` (the `202609290004` body),
  `5db1706b597dfd828b725c658df2dc55` for
  `private.preserve_child_safety_account(uuid)` (the `202609290008` body) and
  `4f0def6c5524d14f3eeb10d8ef087431` for `run_nina_retention()` (the
  `202609290008` body); the consent foreign key read `ON DELETE CASCADE`,
  `family_id` was not null, the reason check listed four reasons, the column
  did not exist, `private.nina_reply_reports` had no `reply_text` or
  `request_text`, and the newest version row was `202610140001`. The
  migration also adds those two columns, which `delete_household` fills for a
  reply still held for review, and redefines `run_nina_retention()` (the
  `202609290008` body plus one statement clearing them 90 days after the
  report). Those pre-checks were run again right before the apply and still
  matched. It went through the Supabase MCP `apply_migration` with the
  committed file's body, and its `schema_migrations` row was set to
  `202610150001` (§12). Read back the same day: the bodies read
  `68a94e31814cf956b285f793cecd4b2d`, `9a956015a0ae0fd7dafc4f63db6c9348`,
  `012635590a2240b8ad04e3e592c69ac8` (`preserve_child_safety_account`),
  `9723c67ffb8e8fa013d2e0f0ade44280` (`delete_family`),
  `f7b1d6693303b3e3a3bde61070efdf50` (`delete_household`),
  `b40485125ad32a93f118120bab887d2b` (`settle_household_ai_runs`) and
  `45b9504c349019282403b680102cb5e4` (`run_nina_retention`), the local
  bodies; `delete_family` is executable by `authenticated` alone and the two
  private functions by no API role; the runbook's grant count reads 52
  `authenticated` and 27 `service_role`; the foreign key reads `ON DELETE SET
  NULL` with `family_id` nullable; the reason check lists `'house_deleted'`;
  the three new columns exist; and the foreign-key index canary reads 0.
  Build 14 ignores the new key and never calls the RPC; "Apagar a casa"
  reaches people with build 15. Terms §5 (the titular leaves by passing or
  deleting the house, behind the house's name typed; deleting erases what the
  house holds for everyone, private memories included; it cancels no Apple
  subscription) was pushed after the apply, in commit 4382db9, and the page
  reads "Atualizados em 15 de outubro de 2026". Heitor decided on 2026-10-15
  that the recorded Terms version follows the page date, so once that page was
  live the operator statement
  `update private.age_policy set current_terms_version = '2026-10-15', updated_at = now() where singleton;`
  ran on 2026-10-15 (`docs/production-launch-runbook.md` §3, "Deleting a
  house"); read back: Terms `2026-10-15`, policy and minor consent still
  `2026-09-29`, so no AI consent was withdrawn.
  Every adult now meets "Os Termos mudaram." once and taps Aceitar, every
  minor acknowledges the Terms again, and a welcome footnote shown before
  that day no longer counts after a relaunch. No migration carries it, as
  with `trusted_assurances`, so the local stack keeps `'2026-09-29'`.
  `/familias/`, `/suporte/` and the in-app FAQ said nothing about how a
  titular leaves, so they kept their 14 October text (until `/familias/` moved
  to 18 October with the rating).
- **Join requests reach Casa live from build 15 (2026-10-15).** No
  migration: the `families` bump already reached production's realtime; the
  app had subscribed twice per cold launch and kept a dead channel, and a
  refresh that regained the house after an unverifiable load never listened
  again (§5, "Debounced realtime"). Builds up to 14 still see a request only
  after a return to the app or a relaunch.
- **The rating is 14 since 2026-10-18 (ClassInd's reading; D1 is over).**
  `NinaRating.currentCode` and `web/src/rating.ts` both say `"14"`
  (`repository.rating-constant-consistency` compares them), and Terms §4
  ("não recomendada para menores de 14 anos"), `/familias/` §11 and the marks
  read the same constant. D1 aimed for "Livre" and accepted 10 or 12. On
  2026-10-15 the ClassInd coordination answered Heitor's written question by
  email: Nina presents D.5.1 (purchases) and D.5.3 (generative AI of broad
  content), so it tends to 14, and no attenuator applies to interactive
  elements. Heitor accepted 14 on 2026-10-18 (option A): the chat and Premium
  stay exactly as they are, for adults only; the next step is the voluntary
  análise prévia through the Sistema ClassInd (the App Store is not part of
  IARC; the filing needs a video of every feature open to classification, plus
  an access link, login and password when full access needs them), not filed
  yet; and if the Ministry rates Nina lower, the constant goes back down. Build
  18 (2026-10-18, tagged `testflight-1.0-18`) is the
  first to carry the 14 mark on the welcome and the startup screen; builds up
  to 17 still draw "L", and from build 19 the app draws no mark at all (§5). The Terms page reads "Atualizados em 18 de outubro de
  2026" and `/familias/` "Atualizada em 18 de outubro de 2026", and once the
  Terms page was live the operator statement moved
  `private.age_policy.current_terms_version` to `'2026-10-18'` on 2026-10-18
  (`docs/production-launch-runbook.md` §3, "The rating of 14, and the Terms of
  18 October"; read back: Terms `2026-10-18`, policy and minor consent still
  `2026-09-29`). Every adult now meets "Os Termos mudaram." once
  and every minor acknowledges the Terms again. The answer, the decision,
  Apple's questionnaire answers and the four questions to ask App Review are
  in `docs/privacy/classificacao-indicativa.md`; how Apple shows a Brazil
  rating of 14 (a direct setting, an override, or only an MJSP assignment) is
  UNVERIFIED. The
  ClassInd pictogram colours and drawing, the CVV number (188), the Polícia
  Federal intake for the child-safety hold and the OpenAI sub-processor link
  are UNVERIFIED and must be read from their official sources before release.
  The App Store name "Nina: sua amiga da casa" still says "amiga", which the
  voice rule for surfaces a minor can see (§2) no longer allows; Heitor
  renamed the listing "Nina: rotina da casa" in App Store Connect on
  2026-10-05.
- **D3 is decided (2026-10-14): self-declared adults chat and buy Premium.**
  Heitor's own Brazilian adult account read `self_declared` on every retry;
  Apple's documentation and WWDC25 session 299 say adults read `selfDeclared`
  by default, Apple's adult-confirmation regions do not include Brazil, and
  the "Confirmação de Idade" row does not exist on Heitor's Brazilian Apple
  Account (checked 2026-10-14). The legal reading (verified age only for
  prohibited content and goods; the ANPD/MJSP/Secom FAQ of 2026-07-30) and the
  cost are in `docs/privacy/lgpd-launch-posture.md`, "Decision D3". Production
  ran the operator statement
  `update private.age_policy set trusted_assurances = '{confirmed,operator,self_declared}' where singleton;`
  on 2026-10-14, right after the push that published Terms §4, privacy §3A
  and §5, `/familias/` and `/suporte/` (the live pages read "Atualizados em 14
  de outubro de 2026" and `data-legal-launch="ready"`). Read-back: the row
  holds `{confirmed,operator,self_declared}`, and Heitor's self-declared
  account reads `may_use_ai` true, `premium_buyer_is_eligible` true and
  `is_trusted_adult` false. The policy needs no migration and no build: the app reads
  `may_use_ai` and `may_buy_premium` from the server. The next build carries
  the new FAQ answer ("Quem pode conversar com a Nina?") and the
  parental-controls gates (§4); until people update, build 12's FAQ still asks
  "Por que a conversa pede idade confirmada?", and an adult with parental
  controls on still reads "A conversa pede idade confirmada." / "A Apple ainda
  não confirmou sua idade." on the chat and "Isso pede idade confirmada pela
  Apple." on the Premium sheet, untrue for them. In every build, two lines
  raised only when the server refuses a device whose reading is stale still
  name Apple's confirmation: the chat's `nina_age_confirmation_required` ("A
  conversa pede idade confirmada.", `MockNinaEngine`) and the purchase's
  `premium_requires_adult` ("Isso pede idade confirmada pela Apple.",
  `PremiumSubscriptionStore`); `age_confirmation_required` on the minor paths
  keeps that line because it is true there. Acting for a minor stays
  `confirmed` or `operator`. The Terms version stayed `2026-09-29` for D3 (the
  change only widens what an adult may do and adds no obligation; it moved to
  `2026-10-15` for the house deletion and to `2026-10-18` for the rating), and the AI consent version stays `2026-09-29`. The expected
  cost was the
  ClassInd self-classification: a self-declared gate is "facilmente burlável"
  for attenuator E.1.10, so purchases (D.5.1) might lift the rating to 14,
  outside D1, and "Livre" stayed published while the written question to the
  ClassInd coordination on Ask to Buy and Screen Time was open. Its answer of
  2026-10-15 read 14 from D.5.1 and D.5.3 and counted no attenuator for
  interactive elements, so the 14 does not rest on the self-declared gate
  alone; Heitor accepted it on 2026-10-18 and kept D3 as it is (the rating
  entry above).
  `private.age_assurance_distribution()` is still read after each round.
- **Not built:** the guardian's "{nome} agora tem conta de adulto." notice (no
  server field says a ward turned 18; the ex-minor does see "Agora a conta é
  sua."), and a PermissionKit flow for `significantAppChangeRequiresParentalConsent`,
  so no update may widen what minors can do while Brazil might require it.

- **The flagship AI feature ships on — decided 2026-09-04.** `NINA_AI_V2_ENABLED`
  is `YES` in `Nina/Config/Nina.xcconfig`, the secrets example, and the
  production inventory; the historical
  default was `NO` pending a test-account rollout, and the paragraph below
  describes what that state meant and the one server-side step the flip still
  requires before the first shipped build. The flag
  has exactly one reader, `NinaProposalGate` in `BackendConfiguration.swift`,
  applied at the live turn (`AppStore.sendMessage`) and the hydration path
  (`RemoteHomeBackend.NinaStateMessageRow.domainMessage`) — so Nina still calls
  OpenAI and still costs money, but every proposal is discarded before it reaches
  the UI. She can talk; she cannot organize. This contradicts the landing page's
  entire three-step promise.

  **What flag-off means, and what turning it on costs.** There is no server-side
  flag: `nina-chat` writes `nina_proposals` unconditionally, so the discard is
  purely cosmetic and the rows accumulate as `pending` until retention rejects
  them at 30 days. Two rules keep that survivable. First, **a server-recorded
  turn has exactly one confirmation path** — its proposal row. `sendMessage`
  drops `response.suggestion` whenever `serverPersisted`, `NinaStateMessageRow`
  never decodes the stored legacy suggestion at all, and `applySuggestion`
  refuses a suggestion no message in the thread carries, so the legacy
  `SuggestionMiniCard` now reaches only `MockNinaEngine` output — the sole
  producer of a `NinaSuggestion` with no backing row, and DEBUG-only since
  2026-10-15. Before this, tapping
  "Criar tarefa" on the legacy card created the task locally and left the
  proposal pending forever: two confirmations, one of them never closed. Locked
  by
  `AppStoreAuthorizationTests.testAServerRecordedTurnDropsTheLegacySuggestionSoOnlyItsProposalConfirms`
  and `…testTheLegacyPathCreatesNothingForATurnTheServerAlreadyRecordedAProposalFor`.
  Second, **the discard is stated, not silent**: a turn whose pending proposals
  were withheld carries `ChatMessage.hasWithheldProposals` and renders
  "Confirmação ainda fechada", the same honesty the web invite page's
  "Verificação pendente" state buys. Flipping the flag to `YES` therefore needs
  one operational step nothing in the source can perform — reject the outstanding
  pending proposals once, server-side, before the build ships. The exact
  statement is in `docs/production-launch-runbook.md` §3; skipping it launches an
  inbox full of stale cards that duplicate tasks when confirmed.
- **Premium gates three resources server-side; the client never routes you to the
  paywall.** Since the 2026-08-09 migrations each marketed benefit maps to a gate
  enforced where the resource is spent: attachments raise
  `nina_attachments_require_premium` inside `begin_nina_chat_run`, the weekly
  digest is behind `private.family_has_premium` in `get_nina_weekly_candidates`,
  and the chat quota is 50 a day per adult for a covered household versus 10 a
  day otherwise (migration `202610050004`, Heitor's call on 2026-10-05; it was
  30 an hour before), both under the house's 100 a day. Two undeliverable
  benefits were deleted rather than left on the sheet. A denial is routed, not
  just told: `ChatComposerNotice.refusal` turns a quota refusal held in
  `AppStore.chatRefusal` into the composer notice "Limite de mensagens. No
  Premium, 50 por dia." with "Ver o Premium", which opens
  `SheetDestination.premium`, for an account that may buy. Since 2026-09-06 the
  paywall shows a moss activation state ("Premium ativo na casa", one cobalt
  "Pronto") the moment the house is covered, reloads the home context after a
  recorded purchase or restore — `householdPremium` comes from the server, so
  without that reload a successful purchase looked like nothing happened — and
  Casa and Hoje carry a `PremiumBadge` in their headers while the house is
  covered; once covered, the same sheet is a management screen (plan, price,
  renewal, status, what is unlocked, one cobalt "Gerenciar na App Store"), and
  the moss activation moment shows only when the house became covered while
  the sheet was open. The first TestFlight sandbox purchase (2026-09-06) was
  refused every time because Apple's verifier cannot run in the edge runtime
  (§7); **premium was proven end to end on 2026-09-07** when the pending
  receipt was redelivered, verified by the WebCrypto path, recorded with
  `family_id`, and the phone read "Premium ativo para a casa inteira". The
  whole flow, the failure, and the evidence per claim
  are in `docs/premium-flow.md`. Apple's server notifications arrive and are applied: on 2026-09-07 a
  `DID_CHANGE_RENEWAL_STATUS` and an `EXPIRED` notification were verified,
  stored, and the subscription row went to `expired` — the whole loop is
  proven in sandbox. The app side was proven on 2026-09-09 in the simulator
  against production with a throwaway house: the Casa header badge, the
  Ajustes block "Premium ativo para a casa inteira", and "Ver a assinatura"
  opening the management screen (screenshot in `docs/premium-flow.md`). Sandbox
  subscriptions expire in minutes, so "Restaurar compras" hours later finds no
  usable receipt on the device and sends nothing — sandbox, not a bug.
- **Legal identity is a company's since 2026-09-30 (D2).** From 2026-09-26
  Heitor was controller and DPO under his own name and CPF; on 2026-09-30 an
  Empresa Simples de Inovação (Inova Simples, natureza jurídica 234-8, Heitor
  its only titular) became the controller, with an encarregado who is not a
  partner or administrator. An Inova Simples company has no legal personality
  of its own, so Heitor still answers for it personally. The values
  (`PUBLIC_NINA_LEGAL_ENTITY_NAME`, `…_DOCUMENT`, `…_ADDRESS`,
  `PUBLIC_NINA_DPO_NAME`, `PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`,
  `PUBLIC_NINA_DPO_CONTACT_EMAIL`, `PUBLIC_NINA_REPORT_CONTACT_EMAIL`, and
  `NINA_CONTROLLER_DECISION_MAKERS` for the preflight) live only in the
  Cloudflare Workers Builds build variables and the untracked
  `config/production.env` — **never in the repo, which is public on GitHub.**
  `legal.ts` freezes them at build time, so a site built anywhere without those
  variables (a local `wrangler deploy`, a new Cloudflare project) publishes
  `data-legal-status="incomplete"` again and the online preflight's
  `deployment.privacy` turns red. `data-legal-launch` reads `ready` only for a
  14-digit CNPJ, an address and a DPO whose name differs from the controller's
  and from every listed decision maker, and `deployment.legal-launch-identity`
  checks the same from the inventory. `privacidade@ninai.app` is a Cloudflare
  Email Routing rule to the encarregado's own mailbox, which forwards a copy to
  Heitor: a rule takes exactly one destination and one action, so a second
  inbox needs forwarding at the mailbox or an Email Worker. The new company
  starts outside the Simples Nacional; its option was approved on 2026-10-07
  with effect from 2027-01-01, so it stays a normal company with no sales
  until then. Heitor approves the child/sensitive-data wording, each
  Law-text-gated line cites its article in
  `docs/privacy/avaliacao-impacto-criancas.md` §9, and Brazilian counsel reviews
  it only if engaged (`docs/production-launch-runbook.md` §7).
- **The App Store Connect record exists since 2026-09-03**: Apple ID
  `6808423946`, listed as "Nina: sua amiga da casa" because the bare name was
  taken, and renamed "Nina: rotina da casa" on 2026-10-05. The number is public (it is the `apps.apple.com/br/app/id…` path) and
  sits in both `.example` inventories. Both subscriptions (Brazil only, Family
  Sharing on) and a sandbox tester exist since 2026-09-04; the server-notification
  URL is `https://apemftmlsjocvifbptum.supabase.co/functions/v1/app-store-server-notifications`
  and is set for both Production and Sandbox (confirmed 2026-09-09). **Version 1.0 build 1 was
  uploaded to TestFlight on 2026-09-04**, archived from the sources tagged
  `testflight-1.0-1`; nothing has been released. The archive passed every
  artifact check of the production preflight; the App Store verifier is
  unset (production first, then sandbox) and stays that way through
  submission, because App Review buys in sandbox (§4). Do not rebuild the website with
  `PUBLIC_NINA_APP_STORE_ID` until the app is actually live — the install badge
  would link to a store page that does not exist yet.
- **The AI eval passes, 26 of 27 on average, since 2026-09-26.**
  `evals/latest-report.json` is a *local* run (`project_ref: "local"`,
  fixtures seeded by SQL, never production) on `gpt-6-luna` at medium effort
  against fixture version `2026-09-26` (27 cases; the 90% bar is 25 of 27):
  26/27, schema 1.0, 0 unconfirmed mutations, 0 private-data leaks,
  `passed: true`. Three runs of the final prompt scored 25, 26 and 27 and all
  passed; every one got the task family right 27/27, every named day on the
  right day and hour (5/5) and every vague phrase undated (7/7), at a median
  US$0.00027 per model turn. Until 2026-09-23 both `gpt-6-luna` and
  `gpt-5.4-mini` averaged 23.3 of 26, most misses a task or reminder coming back
  as a seed, and spoken days ("dia 20", "sexta às 14h", "amanhã às 9h") often
  came back with `due_at` null — Heitor's first production chat on 2026-09-26
  confirmed a "Dia 20" reminder with no date. The fix is three layers: the
  prompt dates every named day from `local_now` and says a period is not a day
  and a part of the day is not a time; `fillMissingDueAt` dates a proposal the
  model left undated from its label or message; the app reads the same forms
  when a label is confirmed or edited. Two prompt lines scope seeds: a seed is
  an intention with no date *and* no timeframe ("mais para frente", "um dia"),
  and an explicit request for a task or reminder, or a period ("neste fim de
  semana"), stays a task or reminder even undated. Before those two lines the
  date rules alone pushed undated tasks into seeds (22–25 of 27). The fixture
  gates dates both ways: `expected_due_local` on `task-explicit`,
  `reminder-explicit`, `reminder-day-of-month`, `document-bill` (`months_ahead:
  1`) and `document-school` becomes the São Paulo instant at request time
  (`Tools/nina_eval_due.mjs`, `acceptance.due_at_on_named_day: 1.0`), and
  `expected_due_at: null` on `task-no-owner` and `medical-organize` is gated by
  `acceptance.due_at_discipline: 1.0`; a `due_at` without an explicit zone fails
  both. The eval scores model plus `fillMissingDueAt`; `due_at_filled` in the
  function log shows how often the model alone missed (0 in every local run so
  far, so the fallback is proven by unit tests). The remaining misses are kind
  swaps inside the family: the boleto as a reminder, the school meeting as a
  task. No case sends an attachment, so reading a photo or a PDF on
  `gpt-6-luna` is unproven; prove one of each before
  `NINA_ATTACHMENTS_ENABLED` turns on. On 2026-09-29 the fixture grew to 38
  cases (the 11 safety and redaction cases above) with three new gates,
  `minor_task_leaks: 0`, `safety_reply_expectations: 1.0` and
  `minor_names_restored: 1.0`, and its seeds now carry confirmed age rows and
  consents with the transfer. Three local runs that day scored 35, 35 and 36 of
  38, all `passed: true`, with 0 private or minor-task leaks, 0 unconfirmed
  mutations and every minor name restored, and they found four defects: a dose
  change beside "lembretes" reached the model, the risk statement was refused
  by moderation without the CVV line (the harness counted any refusal as
  meeting `reply_must_include`), the adult Mirna's workload reached the model
  as the teen Mirna Clara's, and the sexual request was declined with an offer
  of "uma história romântica e sensual". After the fixes one more local run
  scored 36 of 38 (94.7%, `passed: true`, US$0.0087): the dose change and the
  risk statement were answered without the model (the second with 188), the
  sexual case carries `reply_must_exclude ["sensual", "para adultos"]` and
  passed, and the captured bodies sent to OpenAI (135 calls) held no child,
  teen or family name, with the adult Mirna's two tasks as "Adulto 1". The
  misses were document-bill and document-school, the old kind swaps. The runner
  writes to a temp directory, so `evals/latest-report.json` still describes the
  27-case fixture. The weekly insight on `gpt-6-luna` at low effort was 6/6
  schema-valid with no blame, intent or health language, at about US$0.00016
  per household against US$0.0085 on `gpt-5.5`. A local run on 2026-10-05 with
  the search and semente fixes (committed, not yet deployed) scored 37 of 38,
  `passed: true`, every gate at 1.0, 0 leaks and 0 unconfirmed mutations.
- **Production Auth is Apple only since 2026-09-26.** Heitor turned the Email
  provider and custom SMTP off in the dashboard; `/auth/v1/settings` reports
  `apple:true` and every other door false, and `deployment.sign-in-providers`
  passes. The online preflight had 0 failures that day for the first time.
- **TOTP MFA is enabled server-side with zero client support**
  (`[auth.mfa.totp]` in `config.toml`; nothing in `Nina/` references it).
- **iPhone only, decided 2026-09-04.** `TARGETED_DEVICE_FAMILY = 1` on every
  target; the project used to declare iPad with no iPad layout anywhere while
  the landing FAQ said iPhone-first. Declaring iPad again is design work, not a
  setting.
- **Zero snapshot or UI tests** for a design-system-heavy app; SwiftUI views,
  Astro pages, and all network-touching code are deliberately uncovered and
  pushed to the manual TestFlight matrix.
- **The sensitive path nobody has named.** Photographed boletos, prescriptions,
  and school notices go from the phone, through `nina-chat`, to a US model
  provider as `data:` URIs. This is why the App Store labels carry a
  `Sensitive Info` row. Treat any change to the attachment pipeline as a privacy
  change.
  Three rules hold it in place. **Originals are never stored server-side** — a
  bucket plus RLS plus retention would make this path strictly worse, so the
  extraction summary is the answer and the stored original is not. **What the
  device retains is bounded by construction**: `retainedThumbnailData` walks a
  quality ladder and keeps nothing at all above 320 KiB, and the cached snapshot
  holds imagery for only the 12 newest image attachments, so at-rest household
  document imagery is finite rather than growing with the conversation.
  **`extracted` readings are capped at 40 characters** — deliberately shorter
  than a boleto's 47-digit linha digitável, so the panel structurally cannot
  carry a payment capability.
