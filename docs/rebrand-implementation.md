# Nina — the azulejo rebrand, as built

Last updated: 2026-08-12

The 47 Paper boards are now the shipping app. This document records **every place
the build departs from the boards**, and why. It is the companion to
`docs/rebrand-azulejo.md` (the design) and `design-qa-azulejo.md` (the QA rounds).

Scope: the iOS app only. The website is untouched.

---

## 1. What changed, mechanically

39 files, +6,463 / −7,707. The app is **1,244 lines smaller** than before the
rebrand, which is the intended direction: one palette instead of eleven hues, one
text modifier instead of scattered `.font()` calls, one row drawing shared by two
tabs, and 340 lines of iOS-26 glass tab-bar machinery deleted outright.

Rewritten: `Theme`, `Components`, `TodayView`, `TasksView`, `HouseView`,
`NinaChatView`, `Sheets`, `LoginView`, `HomeSetupView`, `OnboardingTutorialView`,
`ProfileEditorView`, `MemberManagementView`, `InviteLinks`.
New: `NinaMark`, `TaskDetailView`, `MemberDetailView`, `WorkloadView`.
Changed behaviour, not just looks: `HouseholdWorkload`, `LocalNotifications`,
`Models` (a new category), the app icon and the accent colour.

**Untouched on purpose.** `AppStore`'s concurrency machinery (context token,
serialized write queue, local revision guard, debounced realtime), the whole
attachment pipeline, `AuthSession`, `RemoteHomeBackend`, `PremiumSubscriptionStore`,
`PrivateLocalDataStore`, `BackendConfiguration`. This was a presentation rebuild
standing on invariants that had no reason to move.

---

## 2. System-level departures from the boards

**Inter became the system face.** The boards set all UI text in Inter. The app
uses SF Pro. Inter and SF Pro are near-twins; bundling a second family to gain
almost nothing costs binary size and gives up Dynamic Type, optical sizing and
the accessibility behaviour iOS provides for free. The design's real commitment —
a serif that reads as a letter from a person, against a neutral sans for
interface — is intact.

**Fraunces is bundled, but as a static cut.** `Nina/Fraunces-Regular.ttf`, 45 KB,
OFL (licence shipped beside it). It is the variable font instanced at
`wght 400 / opsz 72 / SOFT 0 / WONK 0`, then subset to Latin-1 + Latin Extended-A
+ the punctuation pt-BR needs. The variable font could not be used directly: its
default named instance is *Fraunces 9pt Black*, and a 9pt optical design at 34px
is visibly wrong, while setting axes at runtime is exactly the boilerplate this
rebuild was asked to avoid.

**The app is light-only.** `.preferredColorScheme(.light)` in `NinaApp`. The
azulejo palette is a fired tin glaze and no dark counterpart was ever designed or
reviewed; inventing twelve dark values would have shipped a palette nobody looked
at. This also deleted the entire `dynamic(light:dark:)` layer. It is the single
most reversible decision here — a dark azulejo is designable, and the glaze/grout
metaphor has an obvious night version.

**`MemberTone`'s case names outlived their hues.** The raw values (`mint`,
`coral`, …) are wire values on synced rows, so renaming them would break decoding
of cached snapshots and remote rows. They now render as a ladder of neutral ink
tints. People are told apart by initials and weight; colour is spent on lateness
alone.

**Tarefas groups by category, not by `TaskSection`.** Board `T1` shows
CASA · 3 / CONTAS · 2 / ESCOLA · 2 — those are category names, not section names.
`TaskSection` stays in the model and on the wire, but has no UI. **Consequence:
custom task sections are no longer reachable from the app.** They were barely
used (a real household gets one, "Tarefas da casa"), but this is a feature
removal, not only a re-layout, and it is the deviation most worth a second
opinion.

**The tab bar hides on pushed screens.** The boards draw no tab bar on `C3` or
`S2`. Without this the detail footer sat underneath it.

---

## 3. Board elements that were not built, because nothing is behind them

These are places where the board draws a control the data model cannot honour. In
every case the choice was to omit rather than ship something inert.

- **`C3`'s comments and reactions.** There is no comments table and no reaction
  storage. A press-and-hold reaction row that persisted nothing would be worse
  than its absence.
- **`C3`'s provenance date** ("na quinta"). `TaskItem` carries `createdBy` and no
  `createdAt`. The line reads "Rafa colocou isto aqui." with no day.
- **`Z4`/`G1`'s aisle grouping.** `shopping_items` has no category column — and
  `docs/product-depth-backlog.md:515` argues *against* building one, on the
  grounds that aisle layout is per-store and per-city so it degenerates into
  manual sorting, which is the load Nina exists to absorb. The zero state no
  longer promises it. **`G1`'s board is still drawn aisle-grouped; that conflict
  is yours to settle**, and it is already in your vault note.
- **`C1`'s "Li 'sábado' no que você escreveu"** hint. Nothing parses free text
  into a date (`inferredDueAt` parses a *label*, not a title), and the sentence is
  past tense about a Nina action, which the voice rule forbids outright.
- **`O6`'s sign-in buttons inside the tutorial.** `AppRootView.entryPhase`
  evaluates `signedOut` before `tutorial`, so only an authenticated person ever
  reaches that screen. The buttons would have been dead.
- **`D2`'s "Usar o app sem a Nina" button.** No decline call exists, and the
  consent screen cannot leave its tab.
- **`WL-0`'s "Compras"/"Semente" composer chips.** `sendMessage` takes text and
  attachments; there is no capture-mode argument and no draft-prefill path.
- **`WL-0`'s load strip does not tap.** `Route` has no task-list case, so there is
  nowhere for it to go without new routing.

---

## 4. Places the build says something different from the board

- **`S2`'s eyebrow drops "· DOMINGO".** Round 4 established the digest is not
  Sunday-bound: the cron is daily and eligibility rolls in 7-day steps.
- **`C3` provenance, when the creator is Nina**, reads "Veio de uma conversa com a
  Nina." Crediting her as the author would be exactly the past-tense claim about
  her own action that the product forbids.
- **`D3`'s "chega por e-mail em até 7 dias"** is false for this build — the
  privacy export is generated on-device and handed to a share sheet. The row says
  so instead.
- **`D3`'s "conversas somem em 90 dias"** is not provable from the client; the row
  shows the one retention horizon the client does own, 30 days.
- **`D2` says "um modelo fora do Brasil"** rather than the board's "um serviço de
  IA nos Estados Unidos" — the voice rule wins, and it matches the wording round 4
  settled on for the same claim elsewhere.
- **Boards that name Rafa** are ungendered and count-aware in the build: a home
  may have zero or several other adults.
- **`N4`'s two-benefit denial list is one line.** `PremiumGateCard` names the
  ceiling that was actually hit rather than listing everything Premium buys.
- **The proposal card's third exit is "Não"**, per the grammar in
  `docs/rebrand-azulejo.md`, though `O2` and `D1` print "Ignorar".
- **Nina's chat rail marker is the mark, not a flat disc.** The boards contradict
  each other here — `WL-0`'s header draws the cup, `YR-0`/`10J-0`/`12O-0`/`1Q0-0`
  draw a filled circle. The mark won, and it can carry presence state.

---

## 5. Behaviour that changed, not only appearance

- **The task detail screen exists.** `Route.task` had zero call sites; tapping a
  task opened an edit form even for a viewer who cannot edit. Tapping now opens a
  read screen, and `createdBy` — captured on every task since forever — is
  rendered somewhere reachable for the first time.
- **A member tap opens a read-only page**, with the editor behind
  `canEditFamilyMember`. `MemberDetailSheet` had been built and never constructed.
- **An edit conflict can no longer be dismissed.** The old alert called
  `acceptRemoteTaskConflict()` when swiped away — a silent remote-wins that threw
  away what the person had just typed. It is now a non-dismissable sheet showing
  both versions.
- **Long-press opens quick actions** (`C4`), the substitute for the swipe actions
  this app cannot have, because the horizontal drag belongs to the tab pager.
  **This is the one interaction that has never been tested against that gesture
  on a real device**, and it is the first thing to check on TestFlight.
- **The workload portrait is three qualitative bands.** No count, no percentage,
  no ranking. Rows are in household order; unassigned work gets its own house band
  drawn in a different weight rather than a different hue, and is never given a
  face. The message names the person carrying more and contains no number — a test
  now asserts the absence of digits.
- **Notifications lost the field dump.** The body was `"\(owner) - \(subtitle)"`,
  which put a photographed boleto's reading on the lock screen verbatim —
  `CLAUDE.md` §12 already recorded this. Nina now speaks a sentence, and
  `testTheTaskDetailNeverReachesTheLockScreen` fails if the detail ever returns.
- **A new category, `Cuidado`.** The six existing ones are a taxonomy of
  logistics; this names the labour the product most wants to make visible.
  **It needs a matching value in the database category CHECK before it can sync.**
- **New app icon and accent colour**, generated from the mark's own geometry.

---

## 6. Known-brittle, and worth watching

- **The premium denial routes by string equality.** `NinaChatView` recognises a
  denial by comparing the chat line to `NinaEngineError.userMessage`. `AppStore`
  maps engine errors to a plain reply and `ChatMessage` carries no error field, so
  there was no other way to route without changing the store. **Rewording that
  error silently removes the paywall button.** The durable fix is an error kind on
  `ChatMessage`.
- **The proposal card's "Repete" row always reads "Não repete."**
  `NinaProposalPayload` has no recurrence field and nothing writes one, so
  `resolve_nina_proposal` always falls back to `'none'`. The row is true today and
  becomes a lie the day a recurrence field is added.
- **`PremiumPlan.mock.benefits` still lists "Prioridade da Nina"**, which is not
  one of the three server-enforced gates and which the rebuilt paywall no longer
  sells. Worth deleting from `Models.swift`.
- **`proposal.allowedMemoryVisibilities` is still ignored** — both visibility
  buttons always render. Pre-existing, but it is the one field on `NinaProposal`
  that nothing in the app reads.

---

## 7. Verified

- `xcodebuild build` — succeeds.
- `xcodebuild test` — **TEST SUCCEEDED**, full `NinaTests` suite.
- `deno task check`, `lint:deletion`, `test` — 99 passed, 0 failed.
- `deno task preflight:repo` — 0 failures, 1 warning (the pre-existing legal
  placeholder).
- Run on an iPhone 17 simulator: sign-in, all four tabs, task detail, capture
  sheet. Screens compared against their boards; three defects found and fixed on
  the spot (a duplicated system back chevron, a footer clipped by the tab bar, and
  two cobalt controls competing on Casa).

Not verified: the database gate (`deno task db:reset && db:test`) was not run —
no migration changed. The `Cuidado` category is the one thing here that will need
one.
