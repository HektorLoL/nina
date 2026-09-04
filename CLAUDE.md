# Nina — Operating Manual

Last updated: 2026-09-04

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
  profiles managed by adults, never users.
- **The real problem.** Not task tracking — *the negotiation cost of task
  tracking*. Routing coordination through a neutral third party so assigning
  work stops being an interpersonal act. Secondary: reading Brazilian household
  paperwork (boletos, receitas, comunicados escolares) out of a phone photo.
- **Emotional positioning: relief, not productivity.** The design north star
  file is literally `web/design-references/landing-conversa-alivio.png` —
  *conversation → relief*. Login calls her "Sua amiga Nina" — a friend, not an
  assistant. The workload feature is "Sinal de sobrecarga", subtitled
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
   relationship `'IA da casa'`). UI copy: *"Limite: 8 pessoas na casa. A Nina não
   ocupa vaga."*

### Voice

Second-person singular informal (`você`), warm, short sentences, no exclamation
marks, no emoji. Nina is referred to as a person ("a Nina entende"), never as
"the AI" or "the assistant". Read `Nina/MockNinaEngine.swift` before writing any
assistant-facing string — it is the canonical corpus of her voice.

---

## 3. Architecture map

Four surfaces, one product.

| Surface | Stack | Entry point |
|---|---|---|
| iOS app | SwiftUI, iOS 17+, Swift 5 mode, `@Observable` | `Nina/NinaApp.swift` |
| Database | Supabase Postgres, RLS + SECURITY DEFINER RPCs | `supabase/migrations/` (34 files) |
| Server logic | 5 Deno Edge Functions | `supabase/functions/*/index.ts` |
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
- **Only an `owner` changes permission roles**, and `owner` can be neither
  granted nor revoked via any RPC. An `admin` may not modify another
  owner/admin. Nobody removes themselves, the owner, or the assistant row.
- **A claimed member (`user_id is not null`) is forced to `household_role='adult'`** —
  otherwise an admin could demote a real person to `child` and silently strip
  their AI access.
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
- **8 non-assistant people per home**, enforced in three places (trigger,
  `request_family_join` count, remaining-slot arithmetic) under a family
  advisory lock taken *before* any row lock.

### AI

- **Nina never mutates household data.** Four read-only tools; every durable
  change is a proposal resolved by `resolve_nina_proposal`.
- **Confirming a corrected proposal must bind the correction.** Editing a
  proposal's fields before accepting goes through `NinaProposalPayload.edited(…)`,
  which recomputes `dueAt` from the edited `dueLabel` whenever the label changed
  and sets it to `nil` when `inferredDueAt` cannot parse the result. A corrected
  reading that produced an uncorrected `due_at` would make the confirmation
  ritual — the product's whole trust proposition — decorative. Locked by
  `RemoteDecodingTests.testCorrectingWhenAProposalHappensMovesTheScheduledDateAndNotJustTheLabel`
  and `…testAnUnparseableCorrectionLandsUndatedRatherThanKeepingTheModelsDate`.
- **Adults only**, checked in the Edge Function *and* again inside
  `begin_nina_chat_run` so a direct RPC call cannot bypass it.
- **AI consent is a server-side record, not a device flag.** `nina_ai_consents`
  holds one live grant per adult per home and keeps withdrawn rows — LGPD expects
  demonstrable consent, and a reinstall must not read as "never accepted".
  `begin_nina_chat_run` and `get_nina_weekly_candidates` both require a live
  grant, so revoking on one phone actually stops the other adult's chat and stops
  the Sunday insight from shipping member display names to OpenAI.
- **Chat threads are per-adult, not per-family.** `nina_threads` is unique on
  (family_id, owner_user_id); one adult's private conversation must never reach
  another adult's context, tools, or weekly insight.
- **Memories start private.** Sharing is always a separate, explicit tap
  ("Guardar para mim" vs "Compartilhar com a casa"), never a single accept.
- **`store: false` on every OpenAI call.** OpenAI retains nothing. Asserted by a
  source-scanning test.
- **The monthly budget is a database CHECK**, not application logic:
  `reserved_microusd + spent_microusd <= cap_microusd`, US$20/mo interactive +
  US$5/mo insights. Reserve-then-settle: failed runs must still book actual
  spend (`record_failed_nina_ai_run`), or induced failures run past the cap.
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
- **A portrait the snapshot refused to conclude is never drawn.** `HouseholdWorkload`
  returns an inconclusive snapshot below 6 assigned open tasks or 2 carriers, but
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
  profile + photo, AI consent, pending invite → `PrivateLocalDataAccess` →
  `ProtectedLocalDataStore`: SHA256-opaque filenames,
  `completeUntilFirstUserAuthentication`, `isExcludedFromBackup`, 32 MB cap.
  Legacy defaults are removed *only after* the protected write succeeds.
- **Account deletion order is photos → `prepare_account_deletion` → Auth user**,
  each stage aborting the next on failure, plus a `BEFORE DELETE` trigger on
  `auth.users` that re-runs the preparation idempotently to close races.
- **The waitlist unsubscribe token lives in the URL fragment and nowhere else**:
  `https://ninai.app/unsubscribe/#<token>`. A path or query would put a live
  cancellation capability into HTTP access logs.
- **The waitlist never confirms whether an address exists**, and unsubscribe
  never confirms whether a token was valid. Both always return
  `202 {accepted:true}`. Any deviation is an email-enumeration oracle.
- **The raw client IP never leaves the Worker** — only `SHA-256(salt ‖ IP)`.
- **Misconfiguration fails closed, never guesses.** No production fallback
  endpoint or key, anywhere.

### Monetization

- **A purchased transaction is not `finish()`ed until the server records it**,
  or StoreKit loses the redelivery path.
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
- **`NINA_APP_STORE_ENVIRONMENT=production` in production.** Xcode and
  LocalTesting chains are never accepted implicitly; an unrecognized value
  throws rather than degrading.

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
   180ms debounce, awaits pending mutations before refreshing.

Copy the standard method skeleton verbatim for anything new: capture token →
clear `syncErrorMessage` → branch on backend availability → `isSyncingHome = true`
with `defer { finishSyncingHome(ifCurrent:) }` → re-check the token after each await.

**Root routing** (`AppRootView.entryPhase`) evaluates in strict order:
`signedOut` → `tutorial` → `homeLoading` → `invite` → then `homeAccessState`
(`noHome` / `pendingApproval` / `unavailable` / `app`). Four tabs
(Nina / Hoje / Tarefas / Casa) in a **custom pager, not `TabView`**, each with
its own `RouterPath`.

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
  terminal position, a typed gate); negative-but-not-late states use grout + ink.
- `moss #3F6B4A` marks confirmed/done, and only for something a *human* confirmed.
- **Category is a monochrome outline glyph, never a colour.** `MemberTone`'s case
  names are wire values that outlived their hues; they render as neutral ink tints.

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

**Haptics are semantic, not decorative** (`Nina/Haptics.swift`):
`selection()` = navigate/toggle/close/un-complete · `success()` = completion or
successful write · `error()` = validation or network failure (fired from the
store, not the view) · `lightImpact()` = open a sheet or press a chip ·
`warning()` = *arming* a destructive action, right before the confirm alert,
never on the confirm itself. Completing a task fires `success()` but
un-completing fires `selection()` — copy that asymmetry.

**Accessibility:** decorative overlays are `.allowsHitTesting(false)` +
`.accessibilityHidden(true)`. `reduceMotion` must *disable* ambient animation,
not shorten it. Icon-only buttons need an explicit label. `HouseView` collapses
its grid when `dynamicTypeSize.isAccessibilitySize`.

**All UI strings are pt-BR literals inline in the view.** There is no
`Localizable.strings`, no `.xcstrings`, no `LocalizedStringKey`. Introducing
`NSLocalizedString` would be a new pattern, not a fix.

---

## 6. Database

34 migrations, `YYYYMMDDNNNN_snake_case.sql`, applied in filename order. Trust
the filename — on-disk mtimes do not match name order.

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
- **`service_role` holds almost no table grants, by design.** Every privileged
  server path is a SECURITY DEFINER RPC, so the Edge Functions never need direct
  table access. If something fails with "permission denied … TO service_role",
  the fix is virtually always to call the RPC (or, in a test, `reset role`) —
  not to add the grant.

`private` schema holds `nina_maintenance_config` (project URL + 32-byte shared
secret) and is revoked from every client role. pg_cron runs
`nina-daily-maintenance` at `15 6 * * *` → pg_net POST to `nina-maintenance`.

---

## 7. Edge Functions

Five Deno functions, all deployed to production as of 2026-09-04. `verify_jwt`
per `supabase/config.toml`: **true** for `nina-chat`, `premium-subscription-sync`,
and `delete-account`; **false** for `nina-maintenance` (shared-secret header) and
`app-store-server-notifications` (Apple JWS chain is the only trust).
`delete-account` is the one function that imports `@supabase/supabase-js` by its
bare specifier — its lint task forbids an inline `npm:` prefix — so its
`config.toml` entry carries `import_map = "../deno.json"`; without it the
platform bundler cannot resolve the import and the deploy fails with 400.

- **`nina-chat`** — the assistant turn. Order is load-bearing and asserted by a
  test: adult gate → `begin_nina_chat_run` (idempotent on `message_id`, claims
  rate limits, reserves budget) → moderation → deterministic safety shortcuts →
  context → token pre-count → model + tool loop → `complete_nina_chat_run`.
  Model `gpt-5.4-mini` via OpenAI Responses, strict `json_schema`, ≤3 proposals,
  ≤2 extra tool rounds / ≤4 tool calls, 32k input cap, 35s timeout.
- **`nina-maintenance`** — daily retention (`run_nina_retention`,
  `run_waitlist_retention`) *before* any AI work, then ≤25 weekly insights on
  `gpt-5.5` with a `gpt-5.4-mini` fallback.
- **`delete-account`** — all logic is in `_shared/delete-account.ts` behind an
  injectable `DeleteAccountBackend`; `index.ts` is a thin adapter. Body must be
  exactly `{"confirmation":"delete"}`.
- **`premium-subscription-sync`** / **`app-store-server-notifications`** —
  Apple JWS verification via `_shared/app-store.ts`.

**Conventions:**

- Pure logic lives in `_shared/*.ts` with a sibling `*.test.ts`; `index.ts` is a
  thin `Deno.serve` wrapper.
- Every error response is `{"error":"<stable_snake_case_code>"}` with
  `Cache-Control: no-store`. **These codes are API surface** — Swift switches on
  them. Never reword one without updating `NinaEngineError` /
  `PremiumBackendRequestError`.
- Wire JSON is snake_case; TS identifiers are camelCase.
- Money is always integer micro-USD, rounded with `Math.ceil`. Never floats.
- Model ids are compile-time constants; only *pricing* is env-overridable, so a
  deploy env cannot silently swap the model.
- Bodies are read through bounded stream readers, never `await request.json()`.

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
- **`.reveal` starts at `opacity: 0` and only JavaScript clears it**, so the page
  renders blank without it. `web/public/styles/noscript.css` is linked from a
  `<noscript>` in `BaseLayout` to restore it — a linked file rather than an
  inline rule for the reason above.
  CSP is specified in two places that must stay in sync: `web/public/_headers`
  (static assets) and `securityHeaders` in `web/src/worker.ts` (dynamic).
- Client behavior is bound by `data-*` attribute contracts
  (`[data-waitlist-dialog]`, `[data-invite-status]`), never CSS classes.
  Renaming a class is safe; renaming a data attribute breaks a script.
- Two pinned constants couple web to database: `waitlistConsentVersion` and
  `waitlistHealthSchemaVersion` in `web/src/waitlist.ts`. A waitlist migration
  that bumps the RPC's `schema_version` turns `/api/health` red and blocks the
  production preflight until the constant is updated.
- `legal.ts` reads `import.meta.env` at module scope — legal identity is frozen
  at **build** time. Changing a Cloudflare variable requires a rebuild.
- The invite page must never appear to validate a code. An unreachable API
  renders an explicit "Verificação pendente" state (this was a resolved P1).

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
  its `plan(N)`**. A new public table must be added to the explicit 21-name list
  in `rls_policies.test.sql` or the RLS canary silently passes.
- Edge Function logic → put it in `_shared/<name>.ts` behind an injectable
  interface, test in `_shared/<name>.test.ts`, add `index.ts` to `deno.json`'s
  `check` task.
- Worker/Astro logic → extract to `web/src/*.ts`, test in `web/tests/`, add the
  file to `format:web`/`lint:web`.
- New release invariant → a `check(...)` in `Tools/production_preflight.ts` plus
  a `Deno.test` in its test file.

RLS does **not** raise on UPDATE/DELETE — it filters rows. `throws_ok` passes
vacuously; use `pg_temp.affected_rows($$…$$)` and assert 0.

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
deno task check && deno task lint:web && deno task lint:deletion && deno task test
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
xcodebuild test -project Nina.xcodeproj -scheme Nina -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

```bash
cd web && npm ci && npm run build
```

```bash
cd web && npm run build && npm run preview
```

Release gates (see `docs/production-launch-runbook.md` for the full six stages):

```bash
npx deno task preflight:production --env-file config/production.env --online --ios-artifact /absolute/path/to/Nina.xcarchive
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
every collection from `PreviewData` ("Casa Castello", 7 demo tasks), and
`resetActivityState()` is `apply(.preview)`, so any "is the home empty?" check
based on `tasks.isEmpty` is wrong in mock/DEBUG. A real remote household does
*not* get demo data: `loadRemoteState` always assigns a snapshot, and `apply(_:)`
only calls `resetActivityState()` when `state.snapshot` is nil. The one surviving
substitution on the remote path is `PreviewData.taskSections` — a single
"Tarefas da casa" section — when the snapshot's sections are empty. So zero
states *are* reachable for real users and must be designed.

**`toggleTask` on a recurring task does not complete it** — it rolls `dueAt`
forward. Only `.none`-recurrence tasks flip `isDone`.

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

**`restoreSession()` returns `.signedOut` on any thrown error** and runs on every
foreground transition — so a network blip while returning from background bounces
the user to `LoginView` even though the Keychain session is intact.

**Nothing wipes protected local data on plain sign-out.** Only account deletion
does. Household, profile, photo, and consent files persist on disk after
`signOut()`.

**Notification scheduling is capped at 60 requests globally**, sorted by soonest
delivery, with recurring tasks expanded 12 occurrences deep. A busy home silently
loses the tail. **First alerts and follow-up nudges are budgeted separately**:
alerts fill the 60 first, nudges take only the remainder, so a repeat of
something the phone already showed can never evict the one time another task is
announced. One nudge per task, not per occurrence, and a task whose first alert
was dropped gets none. A `.high`/`.urgent` task therefore costs up to two
requests — a household of mostly urgent tasks reaches the ceiling with roughly
half as many. Quiet hours **silence** rather than move: `content.sound = nil`
and `interruptionLevel = .passive`, delivery time unchanged, because the app must
never show one time and deliver another. `UNCalendarNotificationTrigger` carries
no timezone — travel silently reschedules everything to the same wall-clock time.
Notifications carry no `userInfo`, category, or actions, and there is no
`UNUserNotificationCenterDelegate`. **The body never contains `task.subtitle`** —
it used to, which put a photographed boleto's reading on the lock screen verbatim.
Nina speaks a sentence and names only who is holding the task;
`NotificationTargetingTests.testTheTaskDetailNeverReachesTheLockScreen` fails if
the detail ever returns. There is still no preview-redaction control, so the
*title* the person typed does reach the lock screen: never claim otherwise in copy.

**`dueLabel` and `dueAt` can drift.** `inferredDueAt(from:)` parses only a narrow
set of pt-BR forms; anything else yields `nil` and the task shows a due label but
never fires a notification.

**`deno task db:test` runs against the database as it stands, not against the
migrations.** It never applies anything. Editing a migration and re-running only
`db:test` tests the previous schema and passes for the wrong reason —
`deno task db:reset` first. Editing a pgTAP file alone needs no reset. Also note
`supabase start` writes an untracked `supabase/.branches/`; it is ignored, and
must stay ignored, because another session's `git add -A` would otherwise commit
local machine state.

**`deno.json` enumerates individual files, not directories.** A new
`web/src/*.ts` or `_shared/*.ts` module is neither formatted, linted, nor
type-checked until you add it. Likewise `deno task test` globs only
`_shared/*.test.ts`, `web/tests/*.test.ts`, and `Tools/production_preflight.test.ts` —
a test placed elsewhere never runs and CI stays green.

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

**`app-store-server-notifications` is publicly reachable** with no shared secret
or IP allowlist — Apple's JWS chain is its only authentication. Sound, but every
unverifiable POST costs a certificate-chain verification. Apple root certs are
downloaded from apple.com at cold start unless `APPLE_ROOT_CA_PEMS` is set.

**`nina_ai_budget_months` is one global row per (month, purpose), not per
family.** One heavy household can exhaust the US$20 cap and every other user
starts getting 429 `monthly_budget_reached`.

**Moderation runs *after* `begin_nina_chat_run`**, so a flagged message still
consumes quota. This ordering is deliberate and asserted by a test — do not
"optimize" it. Note that document attachments are never moderated; only text and
images are.

**`Tools/run_nina_ai_eval.mjs` mutates real project auth settings**, creates real
Auth users, and deletes a real family. It defaults to the production project
ref. **Never run it against production.**

---

## 13. Known gaps and launch blockers

Honest state as of 2026-08-10. These are facts about the project, not bugs to
fix unprompted.

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
  producer of a `NinaSuggestion` with no backing row. Before this, tapping
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
  and the chat quota splits 30/hour for a covered household versus 10/day
  otherwise. Two undeliverable benefits were deleted rather than left on the
  sheet. What is still missing is client-side: a denial becomes a plain Nina chat
  line (`AppStore.swift` maps `NinaEngineError` to `reply`) with no button to
  `SheetDestination.premium`, and only the attachment gate has a pre-emptive
  affordance (the gold "Documentos" chip). The paywall itself also names none of
  the three ceilings, offers no monthly/annual comparison, and renders "Restaurar
  compras" as the only full-width button while purchase is a small pill.
- **Legal identity is deliberately blank.** `PUBLIC_NINA_LEGAL_ENTITY_NAME`,
  `…DOCUMENT`, `PUBLIC_NINA_DPO_NAME` are all `replace_with_…`. The privacy page
  self-declares `data-legal-status="incomplete"` and the online preflight fails
  until they are real. **Nina cannot legally launch until a Brazilian legal
  entity with a CNPJ and a named DPO exists** — that is a company-formation task,
  not an engineering one. Brazilian counsel must also approve the child/sensitive-data
  wording.
- **The App Store Connect record exists since 2026-09-03**: Apple ID
  `6808423946`, listed as "Nina: sua amiga da casa" because the bare name was
  taken. The number is public (it is the `apps.apple.com/br/app/id…` path) and
  sits in both `.example` inventories. Both subscriptions (Brazil only, Family
  Sharing on) and a sandbox tester exist since 2026-09-04; the server-notification
  URL is `https://apemftmlsjocvifbptum.supabase.co/functions/v1/app-store-server-notifications`
  and still has to be pasted into App Store Connect. Version 1.0 build 1, never
  tagged, never released. Do not rebuild the website with
  `PUBLIC_NINA_APP_STORE_ID` until the app is actually live — the install badge
  would link to a store page that does not exist yet.
- **The last AI eval is stale.** `evals/latest-report.json` is dated 2026-06-15,
  ~7 weeks behind the working tree. It passed (schema 1.0, 0 unconfirmed
  mutations, 0 private-data leaks, median turn US$0.0015) but with 92.3%
  classification accuracy against a 90% bar — two failing cases.
- **`supabase/templates/` auth emails are orphaned** — three bare unstyled pt-BR
  HTML files with no brand, and `config.toml` has no `[auth.email.template.*]`
  block wiring them up. They are copy-paste source for the dashboard only.
- **TOTP MFA is enabled server-side with zero client support**
  (`[auth.mfa.totp]` in `config.toml`; nothing in `Nina/` references it).
- **`TARGETED_DEVICE_FAMILY = "1,2"`** declares iPad support, but there is no
  iPad layout anywhere and the landing FAQ says iPhone-first.
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
