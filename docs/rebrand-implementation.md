# Nina — the azulejo rebrand, as built

Last updated: 2026-10-14

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
- **Long-press opens quick actions** (`C4`), the substitute for swipe actions:
  rows live in a `ScrollView`, not a `List`. (Until 2026-09-23 the horizontal
  drag also belonged to a swiping tab pager; that swipe is gone, see §6d.)
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

## 6b. What round 5 changed

`design-qa-azulejo.md` records the full pass: 82 findings judged, 54 confirmed.
Its systemic finding matters more than any single item — **the rebuild deleted
three working features and left the copy that promises them**: memory
edit/delete, chat-history deletion, and the weekly digest surface the paywall
sells. All three are restored. A rewrite that drops the last call site to a live
store method is deleting a feature, and has to be recorded as one.

Three items in §6 above were resolved by that round and are no longer brittle:
the workload house band is computed rather than pinned, the type system's two
halves now scale together, and rows derive their date label and their lateness
colour from the same source. The premium-denial string-equality routing and the
proposal card's fixed "Não repete" row remain exactly as described.

## 6c. What the 2026-09-08 UX audit changed

The audit (vault note "UX audit 2026-09-08", 435 findings) drove one pass of
fixes. The departures from the boards and from earlier rounds, all deliberate:

- **Selected chips and the selected tab are ink, not cobalt.** Boards `T1`/`H1`
  draw the selected filter in cobalt; the one-cobalt-per-screen rule wins, so
  cobalt now belongs to the screen's single commit (the FAB, a footer button,
  the paywall's buy button). `NinaChip` selected = grout fill + ink stroke;
  unset chips and outline buttons use `control`, the stroke `Theme.swift`
  reserves for unfilled controls.
- **`WL-0`'s load strip is gone.** It never tapped and repeated Hoje's numbers.
- **Task rows wrap to two lines.** `H1` draws one-line rows; real titles were
  truncating at ~18 characters beside the date column.
- **"Remarcar as N" is an ink outline capsule with only the count in
  terracotta**, and it confirms with the target ("amanhã, 09:00") before
  snoozing anything.
- **The chat's sample chips prefill the composer instead of sending.**
- **"Marcar como feita" on a repeating task reads "Feita por hoje"** on the row,
  the detail and the quick-actions sheet. The roll-forward is unchanged.
- **Every failed write is reported by one root toast** (`SyncErrorToast` in
  `AppRootView`), so Casa no longer carries the banner and the other tabs no
  longer stay silent. The store fires `Haptics.error()` from the queue.
- **`NinaButton` has a pending state** (`isPending`): spinner glyph, full
  opacity, disabled. Pending is not the same as disabled.
- **Quiet buttons keep their 26pt look inside a 44pt hit area.**
- **The mock engine names nobody.** "Thor", "Heitor" and "Mirna" left the
  fallback replies; everything it proposes is unowned, and it no longer asks
  for photos while attachments are compiled out.
- **A missed lead falls back to the due moment** instead of dropping the
  alert; the nudge asks ("Ainda está de pé?") instead of asserting a state the
  phone cannot know; owned alerts speak to the owner ("Ficou com você.").
- **A transport failure never signs anyone out** (`AuthSessionRestoration.unreachable`),
  never calls an invite dead, and never cancels scheduled reminders.
- **A recurring occurrence missed yesterday reads late** (decided 2026-09-09,
  "mark it late"). `displayDate` returns the latest occurrence at or before now
  when `dueAt` is in the past; the scheduler still books the next future one.
  Pinned by `TaskAgendaTests.testAMissedDailyTaskReadsAsLateSinceItsLastOccurrence`.
- **The proposal card names every correction field, picks the owner from the
  house** (`TaskOwnerChoice`, never a free text field), **previews the parsed
  date before accept** ("Vai ficar: Amanhã, 09:00" or "Não entendi essa data")
  and shows a failed confirmation on the card itself. "Fechar" became "Pronto";
  the memory card's correction sits in the action block like every other kind.
- **The capture sheet departs from board `C1`'s seven-chip composer**: a visible
  Tarefa / Semente segment with one line each sits under the subtitle, three
  chips (date, owner, category) plus "Mais" unfold recurrence, reminder and
  priority, the commit is a worded button ("Criar tarefa", "Plantar como
  tarefa"), and "Sem data" on a seed is a readable grout label, not a dimmed
  chip. The delete button no longer appears while planting a seed, and the
  category panel's "Criar" is ink so the sheet keeps one cobalt.
- **Type is metered on every list surface** (rows, due labels, chips, buttons,
  tab labels, the capture title via the new `.compose` tier) and the Dynamic
  Type clamp moved from `accessibility1` to `accessibility3`. Chips and buttons
  use `minHeight`. Sites still on a raw `.font` are glyphs and a few editor
  fields; they scale next.
- **44pt everywhere it was smaller**: sheet close discs, the gear, the search
  glyph, the attachment and viewer close buttons, the task-detail checkbox, the
  tutorial's remove disc. Bubbles announce "Nina:" / "Você:", section headers
  carry an `accessibilityValue`, the owner avatar on a row reads the full name.
- **One word per act**: "Sair da conta" on all five sign-out sites (armed with
  `Haptics.warning()`), "email" everywhere, pending labels without dots, "Ninguém
  ainda" for no owner on the card, the detail, the conflict sheet and the
  tutorial, "Sem data · plante depois" for undated seeds, "Conversar com a Nina"
  for every hand-off, "Não repete" as a state, one delete confirmation body,
  disabled opacity 0.4, and the Premium sheet's close disc leading like the rest.
- **The workload portrait uses one threshold for the headline and the bands**
  (`overloadMarginAboveAverage`), so the chart can never contradict the
  sentence; the who-carries-more line renders whenever the portrait is
  conclusive; the inconclusive state says what unlocks it; an owner string that
  matches no member folds into the house band instead of getting a face; the
  axis says what the bands are relative to; the pinned "não para cobrar" bar
  moved into the provenance card; "Ver o que está sem dono" opens Tarefas on a
  new "Sem dono" filter that covers every open unowned task, not only today's.
- **The landing no longer sells document reading** while
  `NINA_ATTACHMENTS_ENABLED` is off: the feature bullet is gone, the privacy
  panel is framed around confirmation and money instead of photos, and the
  paywall heading counts two limits, not three. The copy returns with the flag.
- **Web copy**: the hero says "Ela propõe, você confirma"; one CTA label
  ("Entrar na lista") and the header's copy hides until the hero's has scrolled
  away; a "Quanto custa?" FAQ names the free tier and the price once; step 3
  says only the seed stays undated; "o Nina Premium" on every page; the terms
  say "removida da casa" instead of a leave action that does not exist, and
  link reportaproblem.apple.com; the waitlist dialog asks for the email first
  and its eyebrow is "Aviso de lançamento".
- **Web readability**: every phone-mockup label has a 12px floor via `max()`,
  the floating-note eyebrows are 12px, the dialog error text wins its
  specificity, and the invite code wraps on its own row at phone widths.
- **The last raw fonts on text are gone** (2026-09-09): the login, setup,
  member and profile field wrappers, the chat composer, the proposal and
  suggestion titles, and the photo picker label all go through `.ninaText`.
  What remains on `.font(.system(size:))` is SF Symbols and avatar initials,
  which are glyphs sized to their container and must not scale.
- **Dead code removed**: `NinaText.hero`, `NinaTheme.cobaltDeep`,
  `Radius.chip`, `Haptics.mediumImpact`, `PremiumTeaserCopy.title/subtitle`,
  `AppStore.pendingPriorityTaskIDs` with its two mutators, `MemberDetailSheet`,
  and `SheetDestination.addTaskInSection`. None had a caller; the backlog's
  references to them are historical.

## 6d. What the 2026-09-23 "What I didn't like" pass changed

Heitor's list: tab swipe causes mis-taps and steals the back gesture; too much
text; the login looks unfinished and is not vertically centered; every settings
row has a description; the tutorial has useless text. A Mobbin study of ~90 iOS
screens became `docs/text-rubric.md`, and every screen was re-cut against it.
The deliberate departures from the boards:

- **No swipe between tabs; instant tab switching; edge swipe-back everywhere.**
  The boards assume a paging container. `TabSwipeLock` and the pager gesture are
  gone, and a `UINavigationController` extension re-enables the pop gesture the
  hidden navigation bar had disabled.
- **Login (`L1`–`L8`):** the brand block is centered in the space above the
  actions, and the Apple button, "Entrar com email" and the legal line sit at the
  bottom. Email and code entry moved into a sheet, so the welcome never reflows.
  Tagline: "Conta pra ela o que pesa." The welcome has no cobalt; the sheet does.
- **Tutorial: 3 screens instead of 7.** The three question steps stored their
  answers in local state nothing read, and the "subtract" step left nothing
  behind, so both were removed with their dead types. The confirm step mirrors
  the live card word for word.
- **Settings:** no description line on any row except the account row; state is
  a trailing value ("Desligados", "7 vagas", "Premium"); no intro sentence.
- **Chat:** one centered intro ("Jogue uma lembrança aqui." / "Eu proponho. Você
  confirma."), three chips in one row above the composer, no seeded greeting
  while the intro shows, one disclaimer line per screen ("A Nina pode ler
  errado. Nada entra sem você confirmar."), notices as one line on the composer.
- **Proposal card:** tag "Ainda não existe", title, one meta line of glyph +
  value pairs; no "Quando/Repete/Dono" label column; the primary button label
  comes from the kind ("Criar tarefa" / "Criar semente"), not the model's text.
- **One word per act:** "Sem dono" for unowned everywhere (it was "Ninguém
  ainda" on some surfaces), "Plante depois" for an undated semente, "Não dá para
  desfazer." on every irreversible alert. The unbalanced workload headline is
  "Pesando de um lado", because the eyebrow already says "Sinal de sobrecarga".
- **Vendor names left user copy:** no error string says "Supabase" or "backend".
- **Removed with no reader left:** `CompletedTaskRetention` (the "Concluídas hoje"
  group only ever holds today, so its disclosure note said nothing).

## 6e. What the 2026-09-25 "What I didn't like pt2" pass changed

- **Hoje header:** the date never wraps. The avatar moved to the greeting's row,
  which gives the date line the full width, and "Premium" sits beside the date.
  If a phone is too narrow for both, the badge drops below the date
  (`ViewThatFits`) instead of the date breaking in two.
- **A jump from inside a screen travels; a tap on the bar does not.** "Conversar
  com a Nina" (Hoje, Tarefas, Memórias) and the "Sem dono" shortcut now cross-fade
  with a 32pt slide toward the destination tab's side. A tap on the tab bar still
  switches instantly. With Reduce Motion on, the slide goes and the fade stays.
- **"Na casa" is asked only for an adult.** For a child it repeated Tipo, and for
  a pet it repeated Espécie. A child is saved as "Criança". A pet is saved with
  its species ("Cachorro") as the relationship, because the relationship is what
  Nina's chat context reads, not `pet_species`. A value typed before this change
  is kept. The member screen hides a "Na casa" row that repeats another row.
- **The status-bar cover works.** The 2026-09-08 mask was a 12pt strip that
  `ignoresSafeArea` moved into the middle of the status bar, so scrolled text still
  crossed the clock (audit finding V13). The glaze now fills the whole status bar
  and softens only its last 6pt, so headers at rest are untouched.

## 6f. The child's day (2026-09-25)

No Paper board draws this surface. It is a product decision by Heitor: a child is
a profile adults manage, never a user, so a child sees their tasks on an adult's
phone, and the adult can print the list for the fridge or send it on WhatsApp.

- **Entry: a "HOJE · N" block on a child's member screen, and nowhere else.** It
  reuses `TaskRowView`, so the adult sees the same rows as Hoje, lateness
  included. Under the rows sit one cobalt "Mostrar para ‹Nome›" and two outline
  controls, "Imprimir" and "Compartilhar". With nothing today the block is the
  eyebrow "HOJE" and "Nada para hoje.", with no actions.
- **The child's screen** (`ChildDayView`, a `fullScreenCover` presented from the
  app's root) is the child's name in Fraunces over big cards: a 44pt circle, the
  title at the 27pt sans tier, the hour and the category glyph as a picture cue.
  A tap turns a card moss in place; it never moves or leaves. "Tudo feito por
  hoje." sits below the cards, and the list scrolls down to it when the last
  card is marked, so a long list never hides the hand-back line. Its
  app-switcher cover is the root's own `AppLoadingScreen`.
- **"Segure para sair" is an allowed instruction string**, an exception to the
  rubric's G4: a non-standard gesture needs its label. Leaving takes a 2-second
  hold; the ring under the finger is the only feedback.
- **No child surface shows lateness.** No terracotta, no "atrasada", no date. An
  hour shows only for something that happens today.
- **The printed page uses fixed raw type**, the one sanctioned raw `.font` use:
  paper has no Dynamic Type. It has no background fill, so the paper stays white,
  and its hairlines use `control`, because `line` drops out on most printers.
- **`NinaButtonFace` was extracted from `NinaButton`** with no visual change, so
  a `ShareLink` wears exactly the button's face. The private `ShareButtonFace`
  twin in `Sheets.swift` is gone: the data-export and invite `ShareLink`s now
  wear `NinaButtonFace` too, which moves the export button's stroke from `line`
  (1.24:1, under the 3:1 floor) to `control` and its fixed 50pt height to a
  50pt minimum.
- **"Imprimir" and "Compartilhar" sit side by side only when both labels fit at
  equal widths** (`EqualWidthRow` inside a `ViewThatFits`). A plain `HStack`
  passed the fit check on a 402pt iPhone and then split the row in half, which
  wrapped "Compartilhar" mid-word; there the pair now stacks.

## 6g. What the 2026-09-26 pass changed

- **A child's or pet's profile asks for no note.** The "O que a Nina lembra"
  field is gone from the add and edit sheets for both; an adult's stays. Saving
  a child or pet clears any note typed before, because a pet's note went to Nina
  with every message and nothing on screen showed it any more.
- **"O que a Nina lembra" on a child's or pet's screen is a summary built on the
  phone.** No board draws it.
  - It shows up to three memories that name the member, as each memory's title,
    newest first. A memory only this adult can read ends in a lock.
  - It then shows up to three repeating tasks with their rhythm ("Natação · toda
    terça, 18:00").
  - With nothing found, it is one muted line: "A Nina aprende sobre ‹Nome› nas
    conversas." This is an allowed exception to the rubric's 4-word group line.
  - There is no AI call and no server change. It reads only what this adult
    already sees in Memórias and Tarefas, and never a memory's body or a task's
    detail line.
- **Whose memory is it.** A name counts as whole words, without accents or
  capitals, and the longest household name wins, so "João Pedro" is never
  credited to the father João. A full name counts too: when the father is João
  Pedro Silva, his "João Pedro" never reaches his son Pedro, and Ana Clara's
  never reaches her daughter Clara. A name two people share credits nobody, and
  neither does Nina's own. The name in the empty line follows H8's namesake
  rule, except that Nina's row counts ("Nina Rosa", never "Nina").
- **Sign in with Google, and the new-address line in the email sheet, were built
  in this pass and removed the same day** (§6h). Both reached TestFlight build 7
  (tag `testflight-1.0-7`): the Google row hidden because production reports
  `google:false`, and the new-address line in its email sheet. The next build
  carries neither.

## 6h. Apple only (2026-09-26)

Heitor's decision: no email login and no Google login; Sign in with Apple is
the only way in. No board changes, because the boards draw an Apple button, but
the welcome and Ajustes lose surfaces earlier passes had added.

- **The welcome has one door.** The brand block, the black "Continuar com a
  Apple" button and the legal line. "Entrar com email", its sheet (email and
  code steps) and the Google row are gone, and so is the fade that waited for
  Google's availability check: the button is there from the first frame. The
  welcome is 9 authored words, 20 with the legal line.
- **The error line stays** inside the action group for an Apple failure or an
  unreachable backend; since 2026-10-04 it is red with its glyph
  (`NinaErrorNote`), never terracotta.
- **Ajustes loses "Email de acesso" / "Adicionar email".** The account row still
  shows the address Apple shared, and the profile's Email field stays read-only
  with the "Apple" note. Nothing links or changes a sign-in email.
- **A Debug build keeps two test doors.** One quiet row, "Teste 1 · Teste 2",
  under the Apple button signs in the local test accounts (local home, no
  backend). It is compiled only under `#if DEBUG`, and the release preflight's
  `artifact.debug-sign-in` fails if their addresses reach the bundle.
- **The one door is pinned.** The repository preflight's
  `repository.apple-only-sign-in` fails if any app source calls an email code,
  magic link, password, OAuth or non-Apple ID-token sign-in, or changes a
  sign-in email; the online `deployment.sign-in-providers` fails while
  production Auth has any provider but Apple on.
- **`NinaButton` lost `assetName`** and `Assets.xcassets/GoogleG.imageset` is
  gone, so `Theme.swift` is again the only source of colour.
- **The premium line for an account that cannot buy** reads "Entre com a Apple
  para assinar."

## 6i. Nina for all ages (2026-09-29)

Heitor's decisions D1–D4 (aim for "Livre", a company before launch, only
Apple-confirmed adults act for AI, money and minors, iOS 26.4; D3 changed on
2026-10-14, so self-declared adults now chat and buy, and only acting for a
minor needs Apple's confirmation) plus the build-10 Apple fixes. No board draws any of this; every screen below is built from the
existing parts (`NinaMark`, `NinaButton`, `.ninaCard`, `NinaRow`, `Eyebrow`) and
its strings are in `docs/text-rubric.md` §3, most of them Law-text-gated.

- **The welcome says less and asks the age first.** "Sua amiga Nina" / "Conta
  pra ela o que pesa." became "Nina" / "A rotina da casa, dividida.": a child
  can see this screen, and the old tagline invited emotional unloading (ClassInd
  Guia D.7.1). From 2026-09-29 to build 10, step 1 was one cobalt "Continuar"
  that read Apple's age range before the black Apple button, which asked for
  name and email only for an adult reading. That cobalt age step was removed on
  2026-10-04 (build 11, §6j): the age is read after Sign in with Apple, which
  asked for no scope in build 11 and asks every account for the name alone
  since build 12 (§6k), so rubric L4 is back to no cobalt on the welcome. The
  legal line gains the protected "Menores de 18 anos entram
  numa casa com aprovação de um responsável.", so the welcome is 29 authored
  words, one over the budget; the legal text wins.
- **The ClassInd pictogram is the one colour outside the palette.**
  `NinaTheme.classInd(_:)` holds the six official rating colours and
  `ClassIndMark` draws a rounded square with the code in white on the welcome
  and on the startup `AppLoadingScreen`, as Portaria MJSP 1.048 art. 50 asks
  ("instalação, login e inicialização"); since build 11 there is no settings
  row and it is smaller (§6j). It is
  a named regulated exception to "`Theme.swift` is the only palette": it never
  tints anything else, and the code inside uses `.font(.system(size:weight:))`
  because the pictogram is artwork, not copy. **UNVERIFIED:** the hexes (L
  `#00A859`, 10 `#0095DA`, 12 `#FDC300`, 14 `#F58220`, 16 `#E3001B`, 18
  `#1D1D1B`) and the drawing were not read from the gov.br/mj artwork; replace
  both from the official files before release, in `Theme.swift` and
  `web/src/rating.ts` together.
- **`AgeCheckView`** is a centred gate (G15): the 48pt mark, "Antes, sua faixa
  de idade.", the protected Apple line, one cobalt "Continuar". Declined, Apple
  error and App Attest failure each swap in one headline, one line, a cobalt
  retry and a quiet "Continuar assim". **`AgeMajorityView`** ("Agora a conta é
  sua.") has the same shape with "Aceitar" and a quiet "Ler os Termos".
- **A minor never sees the four tabs.** `MinorRootView` is a single stack:
  `MinorHeader` (the title "Suas tarefas" and the protected second line
  "Responsável: {nome}", G1 live data), then "Hoje" and "Próximos dias" rows
  shaped like `ChildDayRow` (title, hour, glyph, a done control; `success()` on
  done, `selection()` on undone, as in Tarefas). Every other state — no house,
  pending, age required, no guardian, limit reached, removed — is one centred
  G12 block. The welcome card is grout-filled, like the consent card. No
  terracotta anywhere a minor looks: a minor's list, like the child's day,
  never shows lateness.
- **Minor settings** follow S1–S9 with rows only; "O que a Nina guarda",
  "Precisa conversar?" and "Minha idade está errada" are pushed text pages with
  one quiet link each, and "Apagar conta" / "Sair" close the list.
- **The guardian sheets** reuse the capture-sheet anatomy: title, a
  grout-filled card of five lines, two chip rows (none preselected for the
  relationship; Apple's band preselected and older bands disabled), the
  optional nicknames field, two required checkboxes and one optional one in its
  own grout row, then one cobalt "Aprovar" (or "Cadastrar") that is `.disabled`
  and dimmed until everything required is chosen. `lightImpact()` on open,
  `success()` on a recorded approval, `error()` from the store.
- **Supervision on a minor's member screen** is an eyebrow "Supervisão" with
  value rows (G3) and the quiet destructive actions last, in ink; `warning()`
  arms each alert and never fires on the confirm. A claimed minor's row in Casa
  reads "Acesso limitado", a profile without consent "Sem autorização", never
  the band.
- **The member editor's role chips** are "Adulto · Adolescente · Criança ·
  Pet". "Adulto" no longer creates an account-less adult: it shows "Adultos
  entram por convite." and "Convidar"; a viewer who is not a trusted adult sees
  the two minor chips disabled with one helper line.
- **The AI consent card** keeps its headline and button and gains a grout card
  of five lines and a separate grout block, eyebrow "Envio para fora do Brasil",
  with the transfer checkbox; the primary stays disabled until it is ticked.
  "Este aviso mudou." appears above the headline when an older consent was
  withdrawn. The declared-adult and blocked gates follow C14.
- **"Denunciar resposta"** is a context-menu item on every Nina reply in the
  adult chat, opening a sheet of four chips and "Enviar"; the confirmation is
  the one line "Recebido. Vamos olhar." **"Denunciar um problema"** is a
  settings row for every age.
- **"Apagar conta" warns a subscriber** with a grout card above the typed gate:
  "Sua assinatura continua." / "Apagar a conta não cancela a cobrança. A Apple
  segue cobrando até você cancelar." / quiet "Gerenciar assinatura". The
  deletion screen is also reachable with no house (`.accountDeletionSheet` on
  `HomeSetupView`, the pending, decision and unavailable screens, and every
  minor state).
- **The photo line in the composer** became "A Nina não guarda a foto. A OpenAI
  pode guardar por até 30 dias para evitar abuso.", and the Privacidade footer
  names OpenAI and the 30 days; both were untrue before.

## 6j. Build 11 (2026-10-04)

Heitor play-tested build 10 on his iPhone and decided four changes. No board
draws them; they reuse existing parts.

- **Apple first, one button.** The welcome is the brand block, the black system
  "Continuar com a Apple" (52pt, field radius, `requestedScopes = []` for every
  account in build 11; `[.fullName]` since build 12, §6k), the legal footnote
  and the rating mark. There is no cobalt control
  on it. The age step ("Antes, sua faixa de idade.") is now the first screen a
  new account sees after Apple's sheet, so it gained the quiet "Sair da conta"
  and "Apagar conta" at its foot, under every phase but the wait, as the
  majority and Terms gates have; "Continuar" stays its one cobalt control.
- **An adult names themself where the house needs it.** "Seu primeiro nome",
  placeholder "Como a casa chama você", sits under "Nome da casa", under "Link ou
  código" and above "Pedir para entrar" on the invite, in the same grout field
  as its neighbours (`ChosenNameField`), with no helper line. It appears only
  while the profile still reads the server's "Família" (or "Você", or empty),
  and the create or join button stays disabled and dimmed until it holds a
  name. A failed save is one ink line, "Não deu para salvar seu nome. Tente de
  novo.", with `error()` fired by `ProfileStore`, not the view; the create or
  join success keeps its own `success()`. "Sair da conta" dims while the name
  saves, and a save that finishes after the account changed does nothing.
  The tutorial's owner chip reads "Você" instead of "Família".
- **The email rows hide when there is no email.** The Ajustes account row is the
  name alone, and the profile's "Contato" shows only "Telefone"; "Email não
  vinculado" is gone.
- **The rating mark only at login and startup, quieter.** `ClassIndMark`'s
  default is 22pt (was 28 on the welcome and 30 on startup), and both screens
  use it: 16pt above the safe-area bottom on both, so the startup cover fades
  into the welcome without the "L" moving. The "Classificação indicativa" rows in
  adult and minor settings are deleted, and the app-switcher covers
  (`AppLoadingScreen(showsRating: false)`, the root's and `ChildDayView`'s) no
  longer draw it, because resuming is not startup. The colour stays the official
  one; quieter means size and position only.
- **One centred wait with a round disc.** The "Só um instante." Heitor saw was
  `AgeCheckView`'s progress state: its column had no width, so inside the
  `ScrollView` it collapsed to the leading edge, and it drew `NinaMark` in
  `.reading`, whose disc is a 1.29:1 bar meant for the chat's "Lendo". Every wait
  (the age check's requesting and recording phases, the home load) is now
  `AppWaitingScreen`: the 64pt `.rest` mark and the line, centred on the whole
  screen, with the startup screen's 0.98–1.02 breath that Reduce Motion turns
  off. `AgeCheckView`'s column also takes the full width, so no phase can
  collapse again, and the invite's "Conferindo o link." uses `.rest` too. The
  startup `AppLoadingScreen` centres on the physical screen, and its entrance
  scale is dropped under Reduce Motion.
- **Account deletion says what happened.** The single "Não deu para apagar a
  conta agora. Nada foi apagado. Tente de novo." became eight lines, one per
  failure (rubric §2.3), in a grout card above the ink button, announced to
  VoiceOver together with the mail line when it shows. A refusal, an ended
  session, or the second failure in a row (a cancelled Apple sheet counts) adds
  the muted "Para apagar mesmo assim, escreva para privacidade@ninai.app." and a
  quiet "Escrever", so the screen keeps its one dark control and still always
  leaves a way out (App Store 5.1.1(v)). "A conta pode já ter sido apagada."
  pairs "Para confirmar, escreva…" with a quiet "Sair" instead. The ink button sizes with `minHeight` now, so "Apagar a conta de
  ‹nome›" no longer clips at accessibility sizes.

## 6k. Build 12 (2026-10-05)

App Review Guideline 4.0 refuses an app that asks for a name after Sign in with
Apple when Apple could have shared it, and build 11's field asked every new
adult. No board draws this; nothing new is drawn.

- **Apple's sheet offers the name.** The welcome's request asks every account
  for `[.fullName]` and never the email, so Apple's own sheet shows the name
  row; Nina keeps only its given name. The welcome itself is unchanged.
- **The name field is the fallback.** An adult who shared a name reaches "Toda
  casa começa com um nome." or "Entrar numa casa." with no "Seu primeiro nome"
  field, and "Nome da casa" or "Link ou código" submits straight to the action;
  the given name, which waits on the phone from Apple's sheet until then, is
  saved before the house is touched, behind the same "Criando" / "Enviando"
  title, and the tutorial greets the person by it. The field, its copy and its
  disabled button are exactly build 11's when Apple gave no given name.
- **A minor's field is filled in.** "Seu primeiro nome" beside the invite stays
  (`MinorNoHomeView`), prefilled with Apple's given name when there is one, and
  still editable.

## 6l. Owner title, handing over, and the Nina tab (2026-10-05)

No board draws any of these; each reuses a part the app already has.

- **The Nina tab draws the mark.** The bar's first item was the `bubble.left`
  symbol; it is now `NinaMark` at 24pt (the small master), ink when selected
  and muted otherwise, like the other three symbols. Its disc lifts and falls
  back into the cup when a task closes on this phone, a position and never an
  expression, and Reduce Motion keeps it still. The large-content viewer still
  shows `bubble.left`, because it needs a symbol.
- **"Titular" names the owner.** The crown's spoken label, the permission line
  and the access value read "Titular" where they read "Responsável", which a
  guardian sheet also uses for a child's parent.
- **"Passar a casa" sits under Permissão.** In the member editor of another
  adult with an account, the owner sees a quiet "Passar a casa"; it opens the
  deletion's own typed gate in place: one muted line, "Escreva {nome} para
  confirmar", and the ink button, with a quiet "Cancelar". It sends an offer;
  the editor then reads "Esperando {nome} aceitar a casa." over a quiet
  "Desfazer pedido". The receiver answers on a card at the top of Casa
  ("Aceitar", cobalt, and "Recusar", outline, like a join request), and the
  Casa tab carries a dot until they do. Ajustes shows the owner a "Sair da
  casa" row that only explains the order: pass the house, then leave.
- **The Premium chat row reads "50/dia".** The paywall's comparison table drew
  "30 por hora"; Heitor moved Premium to a daily limit on 2026-10-05, so the
  row, the chat's ceiling notice and the FAQ say 50 a day.

## 6m. Phone, pet species and the age retry (2026-10-13)

No board draws any of these; each reuses a part the app already has.

- **"Telefone" takes its shape as it is typed.** `21993972860` reads
  "(21) 99397-2860" and a landline "(21) 3333-4444"; a number whose local part
  starts with 9 is grouped 5-4 from its eighth digit, because every Brazilian
  mobile has nine digits, so the hyphen never jumps back while a mobile is
  typed. Brazil's 55 goes only after a "+" (typed, pasted or autofilled) or
  when more than eleven digits arrive, because 55 is also the DDD of Santa
  Maria; a leading 0 goes, since no DDD starts with 0. A complete number takes
  no more digits wherever they are typed, and a backspace that would only take
  ")" or "-" takes the digit before it. A number stored before the field had a
  shape is reshaped only when it is nothing but one complete Brazilian number;
  anything else ("ramal 12", a second number, a foreign one) opens and saves as
  written, and typing in it stays free until it is a plain number again. A
  caret placed mid-number still jumps to the end after the digits regroup. The
  profile keeps the formatted text (`BrazilianPhoneNumber`); nothing reads its
  digits.
- **A pet's "Espécie" is a menu, and "Raça" is gone.** The field is a grout
  menu, "Escolher" until chosen, offering Cachorro, Gato, Pássaro, Peixe,
  Coelho, Hamster, Tartaruga and Outro; Outro opens a "Qual?" field. The stored
  value is still the plain word. A pet saved since writes no breed, and the
  member screen's "Bicho" row shows the species alone. A breed typed before
  stays in `family_members.pet_breed`, and nina-chat still sends it to the
  model, until that pet is saved again.
- **"Tentar de novo" says when Apple answered as before.** On the chat's age
  gate and the minor screens, a share that left status, band, assurance and
  parental controls as they were reads "A Apple manteve a mesma resposta." in
  ink, with no tick, and only when Apple's own answer is the reading already
  shown; "Faixa atualizada." in moss is kept for a reading that changed. On the
  chat's gate it adds "A conversa abre quando a Apple confirmar sua idade.",
  because a self-declared answer never opens the chat while
  `trusted_assurances` leaves out `self_declared`. Since D3 (2026-10-14)
  production admits self-declared adults, so they meet this gate only before
  the operator statement or after a revert. An adult with active parental
  controls meets "A conversa não abre nesta conta." + "Esta conta tem controles
  parentais ativos. O resto funciona." instead, with no line about Apple's
  confirmation (`AppStore.chatWaitsForConfirmedAge`), the tour's closed line,
  and "O Premium não abre nesta conta." on the Premium sheet, because no
  answer from Apple about the age opens either for them. An operator's mark is
  no longer re-asked of Apple when the required regulatory features change, and
  since migration `202610140001` a signal that leaves the account adult keeps
  the mark (only a minor or declined signal replaces it), so a retry over a
  mark left in place reads "A Apple manteve a mesma resposta.".

## 6n. The tour (2026-10-14)

Heitor asked for the tutorial to read as a demonstration: Nina, beside her
mark, says one line per tab over a small animated example, and the last tap
lands in the app. No board draws it; these are the departures it makes.

- **The tour runs after house setup.** `AppEntryRouting` shows `.tutorial`
  only once the house is authorized, so a new owner meets "Toda casa começa com
  um nome." first and a joiner meets the tour the moment they are approved; the
  tour always ends in the app, never before a house exists.
- **"Demonstração" is a grout capsule tag**, the eyebrow in `muted` on grout
  (the `PremiumBadge` shape), not a bare faint eyebrow: Heitor asked that the
  screen read as a demonstration at a glance, and a bare eyebrow was the
  faintest text on it. The header is chrome, like the bar, so its type stops at
  `xxxLarge` and both the tag and the skip show the Large Content Viewer; there
  the tag and the trailing skip still share one row, and if they ever cannot,
  the skip keeps the trailing edge on a row of its own. On the close the hidden
  skip leaves no empty line. The skip, like every quiet `NinaButton`, is at
  least 44 pt wide as well as tall ("Pular" alone is 41 pt).
- **Fraunces in Nina's tour bubble.** The bubble is the live Nina bubble (the
  cobalt wash, radius 20, 14/12 padding), but its text is Fraunces (`.title` on
  the greeting and the close, `.section` on the tab steps), because these are
  Nina's authored words. The live chat bubble stays SF. On a tab step the
  bubble fills the row, so its right edge meets the tray's on the gutter; the
  greeting and the close hug their text and break between their two sentences.
  Every bubble draws `OnboardingTour.drawnLine`, which binds each line's last
  two words with a no-break space, and binds to the next word every one-letter
  word and the short words "um", "na", "no", "de", "da", "do" and "eu", so no
  bubble ends on one word ("cobrar." alone under "não para") and no line ends
  on "O", "e", "na" or a sentence's opening "Eu" at any width ("…entrou / na
  sua casa.", "…vier. / Eu leio…" on an iPhone SE); VoiceOver reads the line as
  written. "em" stays free: bound to "um minuto," it needs 306 pt of the
  greeting's 292 pt and pushes its second sentence to three lines, so the
  greeting keeps "…abas em / um minuto, só com exemplos." (CoreText, Fraunces
  22 pt at 292 pt and 19 pt at 282 and 255 pt; no other bubble changed its line
  count). At accessibility sizes the greeting and the close drop the 320 pt cap
  and use the gutter, and on a tab step the mark above the bubble is 32 pt, so
  Nina still reads as beside her words and more of the example shows above the
  button.
- **The closed Nina step centres its line.** With the chat closed there is no
  example, so the speech row sits in the middle of the screen, as the greeting
  and the close do, instead of over an empty glaze. Crossing between it and
  Hoje replaces the whole step, as the greeting does, so the mark fades and
  hops in its new place instead of gliding up the screen.
- **A tab-bar map with a grout pill.** Under the cobalt button, 14 pt below it,
  sits a copy of the bar (the bar's own titles, glyphs and Nina mark, no dots)
  with a grout capsule behind the step's tab. The capsule is one width under
  every tab, 76 pt (scaled with the bar's titles, at most the item less 8 pt a
  side), so the slide only moves it and it clears the display's corner curve
  under Nina and Casa. It reaches 4 pt above the glyph and 2 pt below the
  title (`TabBarClearance.tourPillReachBelowTitle`). Above a home indicator
  the map and the live bar keep 2 pt under their titles; where the bar meets
  the display edge (an iPhone SE) both keep 8 pt
  (`TabBarClearance.bottomPadding`, read from the bar's own bottom safe-area
  inset), so the pill ends 6 pt above the edge instead of being cut by it, and
  the map and the bar still line up at the handoff. Before the close each item
  jumps to that tab's example; on the close, where the pill sits under the tab
  the app opens on, an item is the app's own tab: a tap leaves the tour there
  (VoiceOver hint "Abre esta aba.", and no item reads as selected, so
  "Começar" carries the hint "Abre a aba Nina." or "Abre a aba Hoje."; a replay
  names no tab). The bar's `xxxLarge` clamp now holds for its titles too,
  because `.ninaText` meters the sans face at the view's `dynamicTypeSize`. The
  tour leaves by a plain dissolve (it arrives with a 1.01 scale), so the map
  and the real bar cross-fade in place instead of the map drifting outwards.
- **The grout "Exemplo" tray holding a stroked ground card.** Every example sits
  on a grout tray, radius 28, under the eyebrow "Exemplo", and is drawn on a
  stroked ground card inside it, so the live grout parts ("Lendo", the semente
  pill, empty band segments) stay visible. The card sits 12 pt in and takes
  radius 16, concentric with the tray. Under Increase Contrast the tray takes a
  1 pt `control` stroke. Nothing in a tray is a control. The tray hugs its
  example 16 pt under Nina's line, so "Exemplo" always heads the frame it
  labels; whatever the viewport has left falls below it as plain glaze above
  the button. No example changes height on a beat (rows, chips and the
  proposal fade in over room they already hold), so nothing above or below a
  tray moves while it plays. An earlier pass stretched the tray to the
  button's fade and centred its content, which left 70 to 150 pt of empty
  grout above "Exemplo" and under the card on an iPhone 17 Pro and Pro Max and
  read as a broken container. Where the steps scroll
  under the button (accessibility sizes), a 32 pt fade from the glaze marks the
  edge, a matching fade appears under the header once the step is scrolled,
  the scroll indicator flashes once the step's last beat has played and only
  when it overflows by more than that fade (an SE step a few points too tall
  reads complete and does not flash), and every step opens scrolled to its
  top, so a reader who scrolled down one example meets the next one's line
  first.
- **Example rows share one layout.** Live rows each choose between one line and
  a stacked date; an example's rows choose together, so Hoje never shows two
  one-line rows over a stacked one. The third Hoje row is "Lavar a louça", short
  enough that the three hold one line at default size.
- **The pet as a pawprint circle in the Casa strip.** Live Casa draws a pet with
  initials and a "Pet" subtitle; the strip has no room for the subtitle, so the
  pet is a 32 pt grout circle with an ink `pawprint`.
- **The portrait cropped to the two adults.** The example house is drawn by
  `HouseholdWorkload.snapshot`, the live rule, which also returns the pet; the
  tray shows only the two adults' rows, with 22 pt avatars and 20 pt segments
  (live: 26 and 30), and no headline, message or caption, because Nina's line
  says "É para conversar, não para cobrar." The axis labels sit over equal
  thirds (`EqualWidthRow`), so "PARECIDO" is centred over the middle segment;
  where the three cannot share equal thirds (an iPhone SE) or at accessibility
  sizes, the axis gives way to the band said after each name, so the Casa
  example still ends above the button. The band stays in words, so colour is
  never its only sign, but it is quieter than the name: the name in `.body`
  ink medium, then "· mais pesado" in `.label` muted regular on its baseline
  (under the name when the two do not fit one line), as the live axis keeps
  band words faint over the bars.
- **The example house never borrows a real name.** `TourSample.cast(avoiding:)`
  folds every word of the greeting name and of every person and pet in the
  real house (`TourContext.houseNames`, read by `AppRootView` from the
  members, so the tour still reads no store) and takes the first of three casts
  (Dani, Cris, Lia, Paçoca; Rafa, Alex, Nico, Pipoca; Tati, Juca, Bento, Farofa)
  with no word in common, or "Adulto 1", "Adulto 2", "Criança" and "Pet". A
  joiner who lives with a real Cris never sees "Cris · leve" in the portrait or
  Cris handed the late bill on Hoje.
- **The person's message keeps the live chip on one line.** The example's ink
  bubble leaves a 16 pt leading gap (the live chat: 44), so "Autorização da
  escola até sexta" fits one line on an iPhone SE and the Nina example ends
  above the button there in every chat state. The ink bubble and the proposal
  face take radius 12 (live: 20), like the semente pill, so no shape 12 pt
  inside the radius-16 card curves wider than the card.
- **Tarefas draws what "Tudo" draws, then the two lists behind their chips.**
  Nina's line says "tudo por categoria, e as compras também", so the example
  opens on one live category group, "PET · 1" (the live chevron header) over
  the example house's one pet task, "Vacina", a live-anatomy row with its
  date, pawprint glyph and owner. Under it sit two inert `NinaChip`s, "Sementes
  1" and "Compras 1" (the live chips' titles and counts, unset), over the live
  grout "Pintar a sala · Plante depois" pill. Live Tarefas never stacks
  Sementes or Compras inside "Tudo"; they are chips that switch the list, so
  they are drawn as chips, not as group headers. The shopping row ("Café · 1
  pacote") is not drawn: with it the step ran 32 pt past an iPhone SE's
  viewport, and the "Compras 1" chip already says the compras live here, while
  the semente keeps its pill because Nina's second sentence explains it.
  Counts come from the example house (`groupTasks`, `openSeeds`,
  `pendingShopping`), no row repeats one Hoje showed, and the spoken
  description follows the picture ("categoria Pet, 1. Vacina, …. Listas
  Sementes, 1, e Compras, 1. Pintar a sala, plante depois.").
- **Nina stops reading before she proposes, and her mark never leaves.** At
  1.20 s the row's 22 pt mark arrives in its `.reading` presence beside "Lendo"
  (the live `NinaReadingCapsule`), entering the tree as a reading mark so its
  capsule breathes as the live one does; at 2.20 s "Lendo" fades and the disc
  settles into the cup; at 2.42 s the proposal fades in (from 96% scale, at
  its top leading corner) in the same slot. The proposal and its disclaimer
  are laid out from the first frame at zero opacity, so the white card has its
  final height while Nina reads and never grows: when the card grew under the
  proposal's spring, for about 0.3 s the proposal drew past the card's bottom
  edge and "16 out., 09:00 · Sem dono" sat on the grout.
- **No FAB or screen headers in the examples.** Each example draws only the
  object it teaches; the only chips are Tarefas' two inert list chips,
  "Sementes 1" and "Compras 1", because those lists live behind chips in the
  live screen.

## 6o. Fitted sheets, forms that end at their commit, chips that hold one line (2026-10-14)

Heitor sent five screenshots: "Entrar numa casa.", "Editar item", "Editar
tarefa" and "Nova tarefa" each held their fields at the top and their commit at
the foot of the screen with half the screen of empty glaze between them, and a
memory card's "Compartilhar com a casa" wrapped onto two lines. The cause was
one written rule, the rubric's G15 "free space sits above the actions, never
below them", which every form followed with a greedy `ScrollView` or a
`Spacer` plus viewport `minHeight`. G15 is rewritten (the centered blocks keep
the old bullet) and G19 is new. Nothing here adds a word; space is removed or
reorganised, never filled.

- **Capture, edit and decision sheets fit their content.** `FittedSheetLayout`
  (`Sheets.swift`) measures its header, its content inside the scroll view and
  its bar, and sets `.presentationDetents([.height(sum)])`; before the first
  measure it asks for `.medium`, never a zero height. Header and bar are
  `.fixedSize(vertical)` and nothing inside sizes from the viewport, so the
  detent and the layout never feed each other. Heights are read by a
  `GeometryReader` behind each part: `onGeometryChange` and a preference both
  missed the pass after a sheet settles its width (the first layout runs at
  about 148 pt, where a typed title wraps to three lines, and the 222 pt it
  measured then stayed, leaving a 66 pt gap above the chips). Taller than the
  screen, the system clamps it, the column scrolls and the bar stays. A card
  that reaches full height also loses its 8 pt side insets, and its wider
  column holds the same note in fewer lines; the content's height is read with
  its width, and a widening of up to 32 pt keeps the card's height
  (`SheetFit.content(after:height:width:)`), so a note one line from the ceiling
  cannot flip the sheet between card and full height. A first layout at a
  passing narrow width (the 148 pt pass above) is a jump far wider than 32 pt
  and never sets the height. Fitted:
  `TaskEditorSheet` (all four modes), `ShoppingEditorSheet`, the non-buyer
  `PremiumEntryView`, `PremiumBenefitsSheet` when it opens on a covered house,
  `InviteFamilySheet`, `TaskEditConflictSheet`, `ProfileCoreMemoriesSheet` (its
  `GeometryReader` and viewport `minHeight` removed, and 10 pt above and below
  each row so a wrapped detail line no longer sits on its divider),
  `SuggestionDetailSheet`, `TaskQuickActionsSheet`, `MinorHealthConsentSheet`,
  `MinorUsageHistoryView` (which also stops clipping a seventh day under its
  header), `ReportReplySheet`, `AnnouncementsSheet` and `MemberEditorSheet`. The
  member editor was first kept at `.large` as a long form, but a child's, a
  pet's or a new profile's ends about halfway down and left some 360 pt of glaze
  under "Tirar da casa"; fitted, a claimed adult's longer form reaches full
  height and scrolls, its nested guardian sheet is untouched, and its close disc
  sits where every other sheet's does (it was padded twice, 20 pt further in).
  A fitted sheet is only ever the root of a presented sheet; `.large` stays for
  Settings and everything pushed in it, `AccountDeletionView` included, the
  paywall, `GuardianApprovalSheet`, the AI consent sheet, `MinorSettingsView`
  and the full-screen covers. On iOS 26 a fitted sheet floats as the partial
  card `TaskQuickActionsSheet` already used, on the same glaze.
- **The card rides the keyboard.** Seen with the software keyboard on the
  iPhone 17 Pro simulator (the first pass had a hardware keyboard attached and
  saw none): in Nova tarefa, Nova semente, Novo item, Editar tarefa and Editar
  item the card sits on the keyboard with the chips and the commit on it, no
  fallback to `.large` needed. It showed one gap the keyboard-down screens do
  not have: a card keeps the height its home-indicator inset added, about
  28 pt, and with the keyboard covering that inset the column took it as glaze
  between the fields and the chips. The detent gives it back while the
  keyboard rises: while the keyboard is down the card reads its resting bottom
  inset (34 pt on a 402 pt phone, 0 without a home indicator), and the surplus
  is that inset less the 6 pt the card keeps above the keyboard
  (`SheetFit.keyboardSurplus(learned:bottomInset:)`, 28 pt, what the simulator
  measured once the keyboard had landed). A first cut learned it only on the
  first `keyboardDidShow` of a launch, so the first quick-add of every session
  landed on the keyboard and then dropped 28 pt. It is applied 80 ms after
  `keyboardWillShow` (`SheetFit.keyboardHeadStart`), animated over the
  keyboard's duration: applied at once, the card's top dipped 27 to 38 pt
  before the keyboard began to lift it. Traced frame by frame on the iPhone 17
  Pro simulator, "Nova tarefa" and "Editar tarefa" now rise to the keyboard in
  one move with no step down, and lowering the keyboard lifts the card 4 pt for
  one frame before it falls.
  `keyboardDidShow` now only corrects a difference of 2 pt or more, and learns
  only a larger value, because a card clamped under the status bar reads a
  smaller one that is not the phone's. The inset is not read from
  `keyboardWillShow` to `keyboardDidHide`: SwiftUI hands the reader the
  keyboard's own inset (about 271 pt) before the show notification arrives, and
  the hide animation passes through 6 pt, which bobbed the bar. Measuring it on
  every layout instead chased the sheet's own in-flight sizes and overshot to
  the 44 pt cap. `keyboardWillHide` returns it. A long note clamps under the
  status bar with the bar on the keyboard, and "Nome da categoria" scrolls into
  view above the chips.
- **A bar's commit keeps 20 pt from the card's foot.** Where no home indicator
  lifts it (a 375 pt phone), "Salvar", "Criar", "Adicionar" and "Plantar" ended
  8 pt above the card's rounded edge, their corners inside its curve, and 9 pt
  from the screen edge at full height. With the keyboard down the bar now adds
  `12 − inset` below itself (`SheetFit.barBottomPadding`): 20 pt on that phone,
  nothing on a 402 pt one or above a keyboard. That space is added to the
  detent rather than measured with the bar: measured, the bar kept the 12 pt it
  had before the inset was read, and every edit sheet on a 402 pt phone opened
  12 pt of glaze above its chips.
- **The sheet header keeps a close-sized slot on both sides.** The eyebrow sits
  between the close disc and an equal empty slot, with 12 pt above and below
  it; at accessibility3 "Plantar semente" covered its "P" with the disc on a
  375 pt phone and touched it on a 402 pt one. It now wraps between words in its
  column and clears the grabber; at default size the header is the same 60 pt.
- **The member editor's commit rides the keyboard while adding.** "Nome" takes
  focus on arrival, and with the commit at the end of the column "Continuar"
  sat 4 pt under the keyboard, corners and all. While adding, the commit (or
  "Adultos entram por convite." and "Convidar") sits in the bar, 8 pt above the
  keyboard; editing keeps "Salvar" and "Tirar da casa" in the column.
- **An editor holding typed input does not close on a swipe or a tap above it.**
  A fitted card leaves the screen above it tappable (190 pt over "Nova tarefa"
  with the keyboard up, 570 pt over "Editar item" with it down, on a 402 pt
  phone), where the full-height sheet left a sliver, and one stray tap threw
  away a typed title. `TaskEditorSheet`,
  `ShoppingEditorSheet` and `MemberEditorSheet` now carry
  `.interactiveDismissDisabled(hasUnsavedInput)`: while adding, a typed title,
  note or quantity (a person's name); while editing or planting, any field that
  differs from what was loaded. The close button still discards, as
  `TaskEditConflictSheet` already works; nothing new is written. Loading a
  member no longer runs the type chip's defaults, which turned a pet's "Pedra"
  tone into "Névoa" on every open and would have read as an edit.
- **The editor panels moved into the field column.** The date and category
  panels open at the end of the fields, directly above the chips (where the bar
  held them before). The category list is whole, with "Nova categoria" right
  under it: a first cut capped it at 208 pt inside its own scroll, which the
  four default categories fill exactly, so "Nova categoria" sat hidden below a
  clean divider with nothing hinting at a scroll, a scroll nested in the
  column's own. The card grows by the panel, and a clamped card scrolls the
  panel into view, "Nova categoria" right above the chips, 450 ms after it opens:
  a sheet puts its scroll view back to the top while it resizes, so the scroll
  the first cut asked for during the resize never showed. Tapping "Nova
  categoria" now focuses "Nome da categoria" (the one thing to do next is type),
  so on a 375 pt phone, where the field opened below the fold, the keyboard
  comes up and the column keeps the field above the chips.
- **"Apagar" moved into the commit row.** In edit mode the quiet "Apagar" sits
  opposite "Salvar" (VoiceOver reads "Salvar" first); at accessibility sizes it
  ends the field column instead. It never appears while adding or planting. The
  alert, its copy and `Haptics.warning()` are unchanged.
- **"Adicionar e continuar" moved into the commit row too.** While adding an
  item it sits opposite "Adicionar", after the owner chip, so nothing that saves
  comes before the last field. `EditorCommitRow` gives up the commit's arrow
  first, then, where the pair still does not fit one line (a 320 pt phone at
  default size), puts the quiet label on its own line at the field edge with
  the commit under it; no label wraps. At accessibility sizes it ends the field
  column, centred, as "Apagar" does, and a label that wraps there centres
  both lines.
- **A clamped card marks the edge its fields run under.** When the content is
  taller than the card and scrolls, a 1 pt `NinaTheme.line` rule appears on the
  header's foot while content sits above the fold and on the bar's top while
  content sits below it (`SheetFit.slicedEdges`), so chips and a commit no
  longer read as floating on half-cut fields; a card whose fields fit, even
  one that bounces, draws none. Overflow is read from the measured heights of
  the fields and the scroll view, and `onScrollGeometryChange` reports only
  how far the person scrolled: on its own it skipped the layout "Plantar
  semente" settled on at accessibility3, and that clamped card opened with no
  rule above its chips. The task and item editors pad their chip row 10 pt
  below that edge (and their fields 8 pt less at the end, so the resting gap
  and the fitted height are unchanged); at 2 pt the rule doubled the chips'
  own stroke.
- **A memory's trash moved into its edit row.** The reading row is "Editar"
  plus, for a private memory, the protected "Compartilhar com a casa", whole;
  the edit row is "Salvar", "Cancelar", then the trash ("Apagar memória") with
  the same alert. Both rows are `MemoryCardActions`, which stack rather than
  wrap: one line on a 375 pt and a 402 pt phone at default size, stacked on a
  375 pt phone at xxxLarge and at every accessibility size.
- **House setup ends at its commit and opens the keyboard.** "Toda casa começa
  com um nome." and "Entrar numa casa." drop the `GeometryReader`, the viewport
  `minHeight` and both `Spacer(minLength: 32)`: the full-width commit, the error
  line and the quiet alternate follow the field 28 pt below it, the
  `MinorNoHomeView` shape. On arrival and on each switch of path the field the
  person types first takes focus (not under VoiceOver), so the keyboard fills
  what was empty glaze. The mode switch no longer animates under Reduce Motion.
  `InviteAcceptanceView` and every gate stay centered.
- **The task detail's footer is inline.** "Marcar como feita" and the quiet
  "Apagar" follow the quick actions inside the scroll column, the
  `MemberDetailView` shape; board C3 drew them pinned to the foot.
- **Premium management is a column.** A covered house's "Gerenciar na App
  Store" (or "Só quem assina muda o plano.") follows the plan card instead of
  being pinned. A purchase made inside the sheet keeps `.large`, so the moss
  moment never shrinks under the person; the paywall's pinned purchase block is
  unchanged.
- **`NinaChip` holds one line** below accessibility sizes (`lineLimit(1)` and
  horizontal `fixedSize`); at accessibility sizes a lone chip wraps, with 8 pt
  above and below and 18 pt at the sides so a two-line label stays inside its
  capsule. Every `NinaChip` sits in a horizontal scroll, a `ViewThatFits`, a
  single-chip column, a short row with a trailing spacer, or a row this pass
  fixed, so the `fixedSize` never clips.
- **Rows that could wrap or squeeze.** The member editor's permission chips
  and the approval's "Entra como" chips are `ViewThatFits`; Casa's header puts
  the house name and the Premium badge on one line and drops the badge below a
  long name (Hoje's date rule); the member editor hides its "Tipo" eyebrow when
  there is no type to choose.
- **Two labelled buttons stack before either wraps.** A `ViewThatFits` alone
  was not enough for the Tarefas selection bar: it measured "Feitas" and
  "Passar" by their sum, which fit at xxxLarge, and the `HStack` then split the
  row evenly, so "Passar" broke into "Passa / r". "Feitas" and "Passar" now sit
  in an `EqualWidthRow` (the layout the suggestion card and the child's day
  already use), whose ideal width is twice the wider label, beside the trash;
  the bar is `TaskSelectionControls`. Before it stacks it drops the checkmark
  and the two-person glyph, which holds one row through xxxLarge on a 375 pt
  and a 402 pt phone; it stacks only at accessibility sizes.
  The same rule now holds for every paired decision: "Aprovar" / "Recusar" and
  "Aprovar como responsável" / "Recusar" on a join request, "Aceitar" /
  "Recusar" on the house offer (a short "Recusar" keeps its own width beside the
  filling button, then fills under it when stacked), and "Corrigir" / "Não" on
  Nina's task and memory proposal cards (an `EqualWidthRow`). At accessibility3
  each pair stacks instead of reading "Aprov / ar".
- **Headers keep their title whole.** In Tarefas' selection mode "Cancelar"
  drops below the title rather than break "Selecionar" mid-word; on house setup,
  where "Sair da conta" wrapped beside the wordmark at accessibility3, it moves
  into the "…" menu above "Apagar conta". Both are a `ViewThatFits`; nothing
  is added.
- **Left out, on purpose.** A paste button in "Link ou código", `AzulejoBand`
  art or a bigger mark on the setup screens (both fill space), and the shopping
  editor's owner chip beside its commit (crowds a 375 pt phone).

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

2026-10-14, §6o: `xcodebuild test` **TEST SUCCEEDED**, 580 tests, 0 failures;
`deno task test` 369 passed, 0 failed; `deno task preflight:repo` 0 failures, 1
warning (`repository.legal-values`, intentional). On the iPhone 17 Pro simulator
(signed Debug build, the DEBUG "Teste 1" local house): house setup on both
paths, Nova tarefa, Editar tarefa (default, xxxLarge, accessibility3), the date
panel with its calendar popover, the category panel, an eight-line note growing
the card, Editar item, Convidar alguém, Ações rápidas and the task detail all
fit with no gap. A throwaway render (not committed) showed house setup at 375
and 402 pt and the memory card's rows on one line at 375 and 402 pt, stacked at
xxxLarge on 375 pt and at accessibility3, with no label cut. Not seen: the keyboard
(the simulator ran with a hardware keyboard attached, so no software keyboard
rose), VoiceOver order and Reduce Motion; a device pass covers them.

2026-10-14, §6o second pass (the fitted member editor, the panel list and its
reveal, the keyboard surplus, the width hysteresis, paired buttons and
headers): `xcodebuild test` **TEST SUCCEEDED**, 585 tests, 0 failures;
`deno task test` 373 passed, 0 failed; `deno task preflight:repo` 0 failures, 1
warning (`repository.legal-values`). A throwaway render (not committed) hosted
each changed screen in a 402 × 874 window at default, xxxLarge and
accessibility3 and in a 375 × 667 window, and captured the simulator's own
screen with the software keyboard up: every editor card rides the keyboard with
its chips right under the fields and returns to its fitted height when the
keyboard goes; house setup opens with the keyboard on its field and the
commit above it; the selection bar keeps "Feitas" and "Passar" whole at every
size; every paired decision stacks at accessibility3. Still not seen: VoiceOver
order, Reduce Motion, dragging the fields to lower the keyboard, and a
keyboard on a 375 pt phone (the simulator is a 402 pt one); a device pass
covers them.

2026-10-14, §6o third pass (the keyboard surplus known before the keyboard,
the bar's 20 pt floor, the header's close slot, the member editor's commit in
the bar while adding, the unsaved-input guard): `xcodebuild test` **TEST
SUCCEEDED**, 589 tests, 0 failures; `deno task test` 373 passed, 0 failed;
`deno task preflight:repo` 0 failures, 1 warning (`repository.legal-values`).
A throwaway XCTest (not committed) traced the card's on-screen frame every
20 ms with the software keyboard up on the iPhone 17 Pro simulator: "Nova
tarefa", "Novo item", "Editar tarefa" and "Editar item" rise to the keyboard
with no step down and their commit 8 pt above it, and no keyboard of the run
needed a correction after it landed; "Continuar" for a new child sits 8 pt
above the keyboard. Rendered at 402 × 874 and 375 × 667, at default size and
accessibility3: every commit 40 pt from a 402 pt card's foot and 19–20 pt from
a 375 pt one, and "Plantar semente", "Nova semente" and "Editar semente" wrap
or sit clear of the close disc. Still not seen: VoiceOver order, Reduce Motion
and a real device's keyboard timing.

2026-10-14, §6o fourth pass (the selection bar without its glyphs, "Adicionar
e continuar" in the commit row and its stacked fallback, the scroll-edge rules
read from measured heights and the chips' clearance under them): `xcodebuild
test` **TEST SUCCEEDED**, 592 tests, 0 failures; `deno task test` 373 passed,
0 failed; `deno task preflight:repo` 0 failures, 1 warning
(`repository.legal-values`). A throwaway render (not committed) showed
Tarefas in selection mode on one row at default and xxxLarge on 375 and
402 pt and stacked at accessibility3; "Novo item" with "Adicionar e
continuar" opposite "Adicionar" on 375 and 402 pt at default and on 402 pt at
xLarge, on its own line above the commit at xxxLarge and on a 320 pt-wide
screen, with no label wrapped, and centred at the end of the fields at
accessibility3; and "Plantar semente", "Editar tarefa" and "Novidades" at
accessibility3 on 375 pt with the rule on the edge the fields run under, at
rest as well as scrolled, and the chips 10 pt below it. Still not seen:
VoiceOver order and a real 320 pt Display Zoom phone.

Not verified: the database gate (`deno task db:reset && db:test`) was not run —
no migration changed. The `Cuidado` category is the one thing here that will need
one.
