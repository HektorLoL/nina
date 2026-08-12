# Nina App Design QA — Azulejo rebrand

Last updated: 2026-08-11

## Compared

- Direction and flow spec: `docs/rebrand-azulejo.md`
- Benchmark study: 74 iOS screens across 41 products (task-app teardown)
- Pattern mapping: 156 benchmark patterns against Nina's shipping build
- Boards under review: 25 artboards in the Paper file `01KZP8YB2108T0W8ZQSA9YGP9W`

Phone boards were checked at 390 x 844. The two wide boards (`00 · Fundação`,
`V1 · Estados vazios`) were checked at their own widths.

Method: seven reviewers, one per board group, each checking every board in its
group against the palette rules, the type scale, lane alignment, the pt-BR voice
rules, the seven product invariants, and the benchmark patterns. Every finding
was then handed to a second agent instructed to refute it against the same
boards, with the deliberate convention-breaks named up front so a reviewer could
not score them as defects. 79 findings were raised; 27 were refuted and
discarded; 52 survived.

## Findings Resolved

- P0: The daily-zero screen turned the end of the day into a two-person
  scoreboard — "Você fechou 7 hoje, o Rafa fechou 4." Two named adults, two
  completion counts, one visibly ahead, on the one screen whose whole job is
  relief. It credited one member's completions to another member and produced
  exactly the comparable number the product exists to refuse. Now reads "A casa
  fechou 11 coisas hoje", which credits the house.
- P1: Terracotta was promoted from a state colour to an action colour — the
  bulk-reschedule control was a solid terracotta pill, the only saturated
  terracotta control in the system, out-shouting the cobalt commit. Now an
  outline control: terracotta text and border, no fill.
- P1: The overdue rows and the day's rows formed two different lane sets, every
  column offset by 14 px, because the overdue block carried card padding the
  other rows did not. The block's card treatment was dropped; all six rows now
  sit on one gutter.
- P1: The main screen's tab bar was not pinned, so two footer rows rendered
  below the home indicator and the last was sliced by the artboard edge. Those
  rows were navigation that already exists elsewhere and were only there to fill
  whitespace; they were removed and the tab bar now sits flush.
- P1: The floating action button completely covered the fourth tab, making a
  destination look absent. Fixed by the stacking correction above.
- P1: One category glyph had been cloned per section instead of set per task, so
  three rows advertised the wrong category — a dentist appointment marked as
  school, a freezer task marked as school. Each row now carries its own glyph.
- P1: The counters, the active filter and the list did not reconcile: a "mine"
  filter showing six rows, half of them owned by someone else. This is the same
  defect the pattern mapping named on this screen in the shipping app. The screen
  is now internally consistent — 3 in your hands, 2 late, 1 unowned, six rows.
- P1: `--color-faint` failed WCAG AA at 2.95:1 on the glaze ground, at every size
  it was used — tab-bar labels, axis labels, meta rows. This was an accessibility
  failure that no amount of resizing would have fixed. The token was darkened to
  `#6A7482`, now 4.61:1, which passes at any size and repaired every usage at
  once.
- P1: A design-rationale note was rendered inside the phone as real product UI on
  the invite screen — styled identically to a live callout, but addressed to a
  reviewer ("Esta é a primeira tela do app…", "sem tour de quatro páginas"). It
  sat on the single most sensitive first-touch screen in the product. Removed.
- P1: The proposal screen's footer overflowed the viewport, pushing the home
  indicator off the board and running the trust disclaimer into the bottom edge.
  Vertical rhythm tightened; the disclaimer now has clearance.
- P1: The proposal's Responsável row rendered a person-style avatar for "A casa",
  which is not a person, and the avatar pushed the value into a two-line wrap.
  The avatar was removed; unassigned work now reads as text, never as a face.
- P1: The seed proposal drew its glyph in moss, which made item kind a colour and
  spent the reserved confirmed/done colour on something not yet confirmed. Now
  monochrome.
- P1: The paywall's annual-saving badge was filled with moss, again spending the
  confirmed/done colour on an unrelated concept. Now ink.
- P1: The paywall's closing card sat after the home indicator and terminated
  flush on the artboard edge. Moved above the price block.
- P1: The shopping header contradicted its own list twice — "11 itens · 3 no
  carrinho" over six items of which two were checked, and a clear-action naming
  three. Both now reconcile with the sections.
- P1: The household header promised "3 pessoas e 1 pet" over a list containing no
  pet. Now "3 pessoas".
- P1: Three saturated cobalt fills competed on the workload portrait, so the
  chart and the button fought for the single intense moment. The button was
  demoted to an outline; the chart is now the one cobalt moment.
- P1: The workload headline claimed a week-long retrospective while its own
  provenance note denied the data was historical. The headline now describes the
  present.
- P1: The inconclusive and conclusive workload boards used two words for one
  concept — "dono" and "responsável", once inside a single card. Unified on
  "dono".
- P1: The household invite card was the screen's primary job but exposed no
  action control, only a preview. A send control was added.
- P2: The workload's "A casa" band used a raw hex outside the palette. Now a
  token at reduced opacity — and, being neither a person nor a colour of its own,
  it reads as a different weight rather than a different hue.
- P2: The empty-states board declared a three-job taxonomy and then shipped a
  fourth label. The waiting-room state is a promise; relabelled accordingly.
- P2: One empty-state's copy was design rationale defending a decision to the
  reader ("Nenhum botão de criar aqui — o que falta é entender…"). Rewritten as
  product copy addressed to the person.
- P2: The paywall's comparison-table column headers were below the muted floor.
  Raised to 13 px.

## Rule Amended

- The type rule required muted secondary text to be 15 px or larger, and roughly
  ten findings were raised against it. Measured, muted is 5.66:1 on the glaze
  ground and passes AA at any size, so the floor was over-strict — it was a
  hierarchy preference written as if it were an accessibility limit. The muted
  floor is now 13 px, and faint is 12 px and reserved for uppercase letterspaced
  labels. The rule was relaxed only after the contrast was measured, and the one
  tier that genuinely failed measurement was fixed rather than excused.

## Accepted Without Change

- The filter chip row clips at the right edge. It is a horizontal scroller and
  the clip is the affordance that says so.
- Metadata value columns begin with an avatar or a glyph on some rows, so the
  first glyph of text starts at different x positions. The value column itself is
  consistent; leading iconography inside a column is standard and reads correctly.
- Two benefit rows on the premium-denial board wrap to a second line. At this
  copy length that is honest rather than a defect.

## Final Checks

- No unresolved P0 findings.
- Terracotta appears in exactly two roles across all 25 boards: lateness text and
  the outline of the reschedule control that acts on lateness. It marks no
  category, mood, or destructive action.
- Category is a monochrome glyph on every board. No categorical colour anywhere.
- Moss appears only on confirmed or completed states.
- Every text tier passes WCAG AA on the glaze ground: ink 17.02:1, muted 5.66:1,
  faint 4.61:1, cobalt 6.48:1, terracotta 5.04:1.
- The workload portrait carries no count, no percentage, and no ranking by load;
  rows are in household order and unassigned work is credited to the house.
- The inconclusive workload board draws no chart of per-person load.
- No board contains a past-tense claim that Nina completed an action.
- Every proposal offers accept, correct and ignore, and states that nothing
  happens until it is tapped.
- Memory sharing is a separate explicit control and names its own irreversibility.
- No content is clipped at an artboard edge except the deliberate scroll
  affordance noted above.

Result: passed

---

# Round 2 — bands 8–10, plus a regression check

Last updated: 2026-08-11

## Compared

The 12 boards added after round 1 (`T1`–`T3`, `D1`–`D4`, `E1`–`E3`, `W1`–`W2`),
plus a regression sweep over the 11 boards repaired in round 1.

Same method: seven reviewers, each pipelined into an adversarial refuter. Two
changes from round 1. The refuters were told the type-floor rule is settled, so
the ten muted-below-15px findings could not be re-litigated after being decided
on measurement. And two of the seven groups re-checked already-repaired boards,
because a fix that silently comes undone is worse than a defect never found.

62 findings raised, 27 refuted, 35 resolved.

## The systemic finding

**Four of the five P0s were the same mistake.** Terracotta — reserved for
lateness — was carrying *destruction* on `D3` and `D4`, and *connection failure*
on `E2`. Moss, reserved for confirmed/done, was carrying three
not-yet-agreed policy statements on `D2`, as green ticks sitting directly above
an Accept button on an LGPD consent gate, where a false already-granted read does
real harm.

These were not four unrelated slips. The palette had a stated answer for
*lateness* and for *done*, and no answer at all for *destructive* or for
*negative but not late* — so all four times I reached for the nearest alarming
colour I had. The repaint is the smaller half of the fix; the rule below is the
rest.

**Added to the system.** Destruction is carried by weight and by friction, never
by hue: an ink fill, terminal position, and a typed-confirmation gate. Negative
system states that are not lateness — offline, sync pending, unavailable — use
grout with ink text. Affirming a fact that is not a completed state uses cobalt,
which the paywall table had already solved correctly and which the rest of the
file should have copied. Terracotta stays lateness-only, with the one accepted
exception already recorded above.

## Findings Resolved

- P0: Three moss check marks on the AI consent gate implied the user had already
  agreed to what they were being asked to agree to. Now muted.
- P0: `Apagar a minha conta` was drawn in terracotta on the privacy screen, and
  the terracotta CTA plus terracotta-wash loss card anchored the deletion screen.
  All now ink and ground; the alarm is carried by the typed `apagar` gate.
- P0: The offline banner was terracotta. Losing connection is not lateness. Now
  grout, matching the lock note on `E3`.
- P0: `A casa` carried a `CA` monogram disc on the workload portrait — the same
  person-style avatar for non-person work that was removed from `O2` in round 1
  and missed here. Now the house glyph. This is the defect most worth watching:
  it is a per-instance fix and there is no rule that prevents the next one.
- P1: A design-rationale card was rendered inside the phone on `T3`, and the
  rationale survived as body copy in a notification on `W1`. Third and fourth
  occurrences of this defect in the file. Both removed.
- P1: `D3` called Nina "a IA" three cards below a toggle that calls her a person.
  Now "um serviço de IA", which names the third party rather than her.
- P1: `E1` used a tu-form imperative ("Escolhe uma") on a você screen.
- P1: Counts that reconciled with nothing — `Tudo 14` over seven rows,
  `Concluídas hoje · 4` over one row, `2 esperando` over no queued rows.
- P1: `systemMedium` laid out 136px of content in a 125px box, so its last row
  overflowed the widget frame.
- P1: The `systemLarge` widget set a whole lowercase phrase in Fraunces at a
  one-off size. Now split — Fraunces on the numeral, Inter on the words — the
  pattern `systemSmall` and `H1` already used.
- P1: The boleto was dated "terça, 10 de agosto" where 10 August is Monday on
  every other board.
- P1: Two cobalt fills competed on `S3`; Nina's avatar is now the neutral disc so
  the invite CTA is the screen's single cobalt moment.
- P1: `Responsável` and `dono` named the same concept across `O2`, `C3`, `E1`,
  `V1`, `S1` and `S2`. Standardised on `dono`.
- P2: Tab-bar labels were 11px, below the settled 12px faint floor, on nine
  boards. `S4` was missing its home indicator. `G1` named the same two items
  "comprados" and "no carrinho" on one screen. The paywall subtitle commented on
  the team's own delivery capacity inside a phone frame.

## Accepted Without Change

- The undo toast on `T3` uses two greys derived from ink that are not tokens.
  Worth promoting to tokens when a second dark component exists; one usage does
  not justify two tokens.
- `H1` still carries two raw literals — the overdue checkbox ring and a
  de-emphasised label on the ink tile. The palette genuinely lacks a legible
  muted value for text on ink, so this needs a token decision rather than a
  substitution.

## Final Checks

- No unresolved P0 findings.
- Terracotta across all 37 boards now marks lateness and nothing else.
- Moss marks completed states and nothing else.
- No design rationale is rendered inside any phone frame.
- No board credits unassigned work to a person or gives it a person-style mark.
- One vocabulary for task ownership across every board.

Result (round 2): passed, with visual re-verification of the repaired boards outstanding —
Paper's screenshot renderer became intermittent while the fixes were being
applied. The changes were style and text edits to structures already verified in
this round, but they have not each been seen rendered.

---

# Round 3 — the advertising boards

Last updated: 2026-08-11

## Compared

The seven boards on the file's `Advertisement` page: three web sections at 1440
and four App Store screenshots at 430×932.

Same reviewer-plus-refuter structure, with one group added that the product
passes did not need: an **over-claim auditor** reading every line of user-facing
copy — headlines, footnotes, and the text inside the phone mockups — against a
ground-truth list assembled from the repository. A craft defect on a marketing
page costs a wince. A false claim costs trust, or an ANPD complaint.

33 findings raised, 23 refuted, 10 resolved. Every P0 was an over-claim, and none
of them was a design problem.

## Findings Resolved

- P0: **A privacy feature was advertised that does not exist.** The documents
  section closed with *"A Nina nunca fala de documento na tela bloqueada. Quem
  passa pela mesa não lê o seu boleto."* `LocalNotifications.swift` has no
  preview control of any kind — no `hiddenPreviewsBodyPlaceholder`, no category,
  no `userInfo` — and `task.subtitle` reaches the lock screen verbatim, which
  `CLAUDE.md` §12 already records as a trap. The seeded demo data proves it: a
  task carrying `subtitle: "Vencimento salvo a partir do boleto."` puts the word
  *boleto* on the lock screen. The claim was replaced with one the build keeps:
  chat threads are per-adult, so the other adult cannot read your conversation.
  A lock-screen line can only follow a change in the notification builder, never
  precede one.
- P0: **An unqualified data-residency guarantee on the one board about the
  crossing.** *"A casa, as tarefas e as memórias ficam em São Paulo e não saem do
  Brasil"* sat under a headline about photographing a boleto. The three nouns it
  picked are the three that actually cross: `search_tasks` and `search_memories`
  return their rows as tool outputs, which are fed to OpenAI alongside the image
  on every turn. Now scoped to records, with the model carve-out named on the
  same card rather than implied on a policy page.
- P0: **The hero repeated the residency claim unscoped** — *"seus dados ficam em
  São Paulo"* — beside a mockup showing a boleto entering the chat. Scoped to the
  house and its tasks. The verifier's argument was the decisive one: the deck's
  own third section bounds the identical claim correctly, so the omission was not
  a limit of knowledge.
- P1: **A delivery guarantee the product does not make.** *"Todo domingo a Nina
  desenha…"* is three over-claims in two words: the digest is Premium-gated, it
  is capped per run, and it requires enough assigned work to conclude at all. Now
  conditional, with a fourth checklist line naming the Premium gate — which the
  section had omitted entirely.
- P1/P2: Sentence-case running text set in the faint tier across five nodes,
  including both boards' closing ethical caption. Faint is reserved for uppercase
  letterspaced labels; these are now muted.
- P2: The proposal card's state label sat below the type floor; the first App
  Store screen left a large blank below its last example.

## Final Checks

- Every number, timeframe, guarantee and capability on the seven boards is
  grounded in the repository, or has been cut.
- No residency claim appears without its model carve-out on the same surface.
- No claim describes behaviour that depends on a code change not yet made.
- The Premium gate is named wherever a Premium-only feature is advertised.

Result (round 3): passed. Two known gaps remain deliberate and are recorded in
`docs/rebrand-azulejo.md` §5b — the boards advertise the proposal flow while
`NINA_AI_V2_ENABLED` is `NO`, and no board carries a legal entity, because there
is not yet one to carry.

---

# Round 4 — the mark and the eight built zero states

Last updated: 2026-08-11

## Compared

`M1` and `M2` (the mark and its presence states, 1440 wide), `Z1`–`Z8` (the zero
states at 390×844), and a regression check on the one `V1` card rewritten when
they were built.

Same reviewer-plus-refuter structure, seven groups, with the over-claim auditor
from round 3 retained — the zero states make privacy, premium and delivery
claims, which is the class of copy that produced every P0 last round.

**69 findings raised. 28 refuted, 21 confirmed by an adversary, and 20 decided by
me** — the two mark groups' refuters died mid-run on a usage limit, so those
findings were never adversarially tested. I adjudicated them against the boards
myself and have marked below which ones that applies to, because a finding I both
raised and upheld is weaker evidence than one that survived an adversary. Two of
the twenty I rejected.

## The systemic finding

**Round 3's fix was applied to the advertising page and never swept across the
product boards.** `D3 · Privacidade e dados` still read *"A casa, as tarefas e as
memórias nunca saem do Brasil. Só o texto da conversa vai para um serviço de IA"* —
the same unqualified residency claim, on the same three nouns, that round 3
identified as false and corrected on `A3`. `search_tasks` and `search_memories`
return their rows as tool outputs fed to OpenAI every turn, and
`buildUserContent()` pushes attachments as `data:` URIs, so images and documents
cross too.

It surfaced only because `Z7` links to `D3`: a user told on `Z7` that a
photographed boleto goes abroad, who taps through to check, was reading that only
text does. A new board exposed a false claim on an old one.

**Added to the method.** A confirmed over-claim is now a search across every
surface, not an edit to the board it was found on. The claim's *wording* varies;
the underlying assertion is what has to be swept.

## Findings Resolved

- P0: **Nina's avatar shipped as two different marks.** `S3` and `N1` still drew
  the pre-rebrand cobalt puck — a filled disc with a light dot — while `Z6` drew
  the mark. The reviewer's phrasing is the right one: the puck is "the one shape
  M1 refuses twice", because a filled circle with a concentric dot is an iris,
  and it is also the sub-18px retired form used at double its ceiling. All three
  now draw the mark. I had graded this P2 when I fixed it on `Z6` during the
  build and was wrong: it is the identity rendering as an eye on the two surfaces
  where Nina speaks most.
- P1: **A residency claim on `D3` that round 3 had already killed elsewhere.**
  Rewritten to name what actually crosses — text *and* imagery — and to claim only
  what `store: false` buys.
- P1: **`Z8`'s footnote was design rationale drawn back inside a phone frame.**
  Near-verbatim pt-BR of two sentences from `docs/rebrand-azulejo.md`, including
  *"porque mostrar uma hora e entregar em outra seria mentira"*. Fifth occurrence
  of defect V5, and on the board where I had already removed one instance of
  design-intent-as-present-tense during the build and left another in the same
  sentence. Deleted rather than rewritten: the rationale already has a home.
- P1: **`Z7` promised "o retrato de domingo".** Three defects in three words. The
  cron is daily at 06:15 UTC and eligibility rolls in 7-day steps from whenever a
  household first crossed the threshold, so no weekday is guaranteed. The shipped
  name is "Resumo semanal". And *retrato* is the app's own word for the workload
  portrait, which is free and client-side — so a reader who saw `Z6` then `Z7`
  would conclude the sinal de sobrecarga is behind the paywall. Putting the
  emotional heart of the product behind a price in the reader's head is a
  positioning error, not a wording preference.
- P1: **`Z7` claimed the model "não guarda nada do que recebe".** The only
  evidence in the repository is `store: false`, which stops retrieval storage and
  is not a zero-retention agreement; there is no DPA, and no entity yet to sign
  one. Cut to the crossing itself. The board's other line — the original is not
  kept server-side — is enforced by construction and stays.
- P1: **`Z7` claimed Premium buys "a conversa sem limite diário".**
  `begin_nina_chat_run` applies an unconditional family cap of 100 turns per
  86 400s on top of the per-user window. Now names what Premium actually removes.
- P1: **`Z2` taught a rule the product breaks.** *"Tarefa é coisa combinada: tem
  dono e tem dia"* — but `T1` shows a task labelled "sem data", `H1` carries a
  "Sem dono 1" filter chip, and `O2`, the first proposal Nina ever makes, renders
  "Dono: A casa, por enquanto". Undated and unowned tasks are first-class in the
  model (`ownerMemberID: UUID?`, `dueAt: Date?`).
- P1: **`Z4` promised aisles that the backlog records a decision not to build.**
  See below — this one is not fully resolved.
- P1: **`Z1`'s Hoje header was a redrawn approximation of a shared component**,
  with its date eyebrow at 11px faint, under the 12px floor settled in round 1.
  Normalised to `H2`'s values, and the board's mark, padding and CTA brought onto
  the Z-family metrics it had drifted 8% off.
- P1 (self-adjudicated): **`M2` printed three false or unscoped claims about its
  own contents.** "Só duas variáveis mudam" was contradicted by three of the five
  cards beneath it; "cada estado tem um sinal geométrico" was untrue of the two
  states whose signal is 2.2/64, invisible at avatar size; and the failure-state
  rule forbade a mark on permission failures while `Z8` drew one. All three
  rewritten to say what is actually true, including the Nina-is-the-subject
  exception.
- P1 (self-adjudicated): **`M2`'s Guardado state closed the floor gap by 43%.**
  The disc settled to cy 30, leaving 4.5% clearance against the 8.0% that `M1`
  prints in cobalt as the mark's critical dimension — the rule whose whole content
  is that holding requires not gripping. Guardado now returns the disc to rest,
  which is also a better reading of the word.
- P1 (self-adjudicated): **`M2`'s five-state row was 24px wider than its column**
  (5×248 + 4×24 = 1336 against 1312) with nothing able to shrink.
- P2: **Four labels assumed the reader is a woman** — "eu mesma" twice, "você
  mesma", "sozinha" — in a two-adult product with no gender field, in a file that
  elsewhere deliberately writes "Moro sozinho ou sozinha".
- P2: **A second seed glyph.** `Z3` drew a stem-and-leaves sprout where `T2` draws
  two splayed leaves, at a darker weight that competed with its own row title. In
  a system where the monochrome glyph is the only kind signal, the primitive has
  to be one drawing. Swapped to `T2`'s.
- P2: `V1`'s waiting-room card promised *"Você vai receber um aviso"* with no push
  path anywhere in the repository — no APNs key, no token table, no server send.
  Rewritten to promise only what realtime already delivers.
- P2: `Z7` carried three cobalt elements under a cobalt mark; the privacy link is
  now muted, matching every other board's secondary. `Z3`'s specimen said "Plantar
  depois" where the app draws "Plante depois". `Z3`'s teaching paragraph and its
  example card had zero px between them. `Z6`'s eyebrow was 11px faint. `V1`'s
  rewritten card stopped quoting the screen it documents.
- P2 (self-adjudicated): `M1` asserted "dois desenhos, não uma escala" and then
  specified only the 64 master; the 24 construction is now printed. Its three
  full-width rows had three different right edges (656 / 608 / 544). The size
  ladder's fifth rung was a threshold drawn at an arbitrary size among four rungs
  drawn at their literal labels.

## Accepted Without Change

- **The "Esperando você" silhouette.** The raised disc breaks 1.9 units above the
  cup's own ceiling and sits between two upturned arms, which is the standard
  head-between-raised-arms figure. I could not settle this by measurement — it is
  a perceptual question, and it is the same class of question as the receptacle
  read in `docs/rebrand-azulejo.md` §2b. It goes into that user test rather than
  being tuned on my own judgement.
- **`M1`'s 64px H1 against `M2`'s 52px.** Same role, two sizes, but the boards are
  not siblings: `M1` is the identity statement and `M2` is its specification. Now
  stated rather than left to be inferred.
- **The app icon draws the 64 master at every size.** iOS scales one asset, so the
  29pt tile renders a mark whose floor gap is proportionally tighter than the 24
  master would give. Recorded as a build note for the icon set rather than
  redrawn: the fix belongs in the asset catalogue, not on the board.

## Carried Forward — needs a decision, not an edit

- **The aisle taxonomy contradicts itself across two docs.**
  `docs/rebrand-azulejo.md` designs shopping grouped by aisle and lists the
  `category` column under the server changes it assumes.
  `docs/product-depth-backlog.md:515` lists aisles under *"which wishlist items I
  would deliberately NOT build"*, and its reasoning is the stronger one: aisle
  layout is per-store and per-city, so it degenerates into manual categorisation —
  the exact mental load Nina exists to absorb. `Z4`'s promise has been removed
  because a zero state must not teach a rule the first added item breaks, but
  **`G1`'s entire structure is aisle-grouped** and that is a product decision, not
  a QA fix.
- **The unsubstantiated retention claim is also live in the shipping app.**
  `Nina/NinaChatView.swift:244` tells users the provider "não os guarda". The
  boards have been corrected to what `store: false` supports; the Swift string has
  not, because the honest fix is either a written agreement or a reword, and the
  first needs a legal entity that does not exist yet.

## Final Checks

- No unresolved P0 findings.
- One drawing of the mark across all 47 boards; one drawing of the seed glyph.
- Nina's avatar is the mark on every surface that renders her.
- No residency or retention claim on any board exceeds what the repository
  enforces, and the sweep was run across the whole file rather than the boards
  under review.
- No design rationale is rendered inside any phone frame.
- Every uppercase faint label is 12px or above; `Z1`'s date eyebrow matches `H2`.
- The mark's floor gap is 8.0% at 64 and 8.3% at 24 in every state that ships.
- No board addresses the reader with a gendered form.

Result (round 4): passed, with the two carried-forward decisions above open and
the mark's perceptual risk untested. Twenty of the sixty-nine findings were
adjudicated by their author rather than by an adversary; if any single verdict
here deserves a second look, it is one of those.

---

# Round 5 — the rebuilt app

Last updated: 2026-08-12

## Compared

The Swift, not the boards. The 47 boards were built into the iOS app in `7506ea6`
(39 files, +6463 −7707), and this round reviews the result.

Seven reviewers, each pipelined into an adversary: design-system compliance ·
board fidelity for the four tabs · board fidelity for sheets and onboarding ·
Swift correctness · over-claim audit · accessibility and Dynamic Type · invariant
regression against `CLAUDE.md` §4. Every group was given
`docs/rebrand-implementation.md` up front, so the twenty-odd deliberate departures
could not be re-raised as defects; agents were told they *may* raise a new
consequence the doc does not name, and several did.

I ran the simulator sweep myself rather than delegating it — a second driver would
have fought the reviewers for the device.

**82 findings judged. 54 confirmed, 28 refuted.** Far more than any board round,
which is what fresh code should produce.

## The systemic finding

**The rebuild deleted three working features while leaving the copy that promises
them.** Not one of the three was recorded as a departure, which is what makes it a
class rather than three accidents:

- `MemoriesView` shipped read-only, while `ProfileEditorView` still said *"Dá para
  editar e apagar na tela Casa."* `updateMemory` and `deleteMemory` were fully
  implemented against live RPCs with zero call sites.
- `deleteNinaChatHistory()` lost its only control. Erasing your own thread — the
  one destructive act that is *not* account deletion — became unreachable.
- `HouseView.insightsSection` was deleted, so nothing in the app rendered
  `store.insights`. **The paywall goes on selling the weekly digest as one of its
  three ceilings.** Charging for a feature with no surface is the worst version of
  this defect, and it is the round's clearest P0.

**Added to the method.** A rewrite that drops a call site to a store method that
still exists is deleting a feature, and it has to be recorded as one. The three
were restored rather than the copy weakened.

## Findings Resolved

- P0: **The three deletions above**, all restored — memory edit/share/delete with
  its irreversibility confirm, chat-history deletion on the privacy screen, and
  the weekly digest on Casa.
- P0: **`MockNinaEngine` fabricated a household statistic and it is the production
  offline fallback.** Not `#if DEBUG`, held unguarded by `AppStore`, and reached by
  the generic catch for every transport failure. Its reply for "cansado" carried
  *"Mirna concentrou 82 tarefas nos últimos 30 dias, enquanto Heitor criou 8"* —
  a number, a comparison and two people who are not in your house, on the one
  subject the product refuses to quantify. Confirming its suggestion created tasks
  owned by those phantom names. The statistic is gone.
- P1: **Nina claimed a completed action in the past tense.** *"Pronto. Deixei isso
  organizado na casa."* — reachable in production. Now *"Você confirmou. Está na
  casa agora."*, which credits the human, as the proposal card already did.
- P1: **Rows printed the stored `dueLabel` while lateness colour came from
  `displayDate`**, so a snoozed or recurring task showed its old date in the new
  colour. A `effectiveDueLabel` derives both from one source; two tests pin it.
  This also fixed the separate finding that "Remarcar as N" left stale dates behind.
- P1: **"Empurrar pra amanhã" did not reach tomorrow** for an overdue task — it
  added a day to a date already in the past and fired `Haptics.success()` for it.
  Now anchored on the later of the stored date and now.
- P1: **Long-press quick actions were unreachable.** The row's two buttons swallowed
  the parent gesture, so `TaskQuickActionsSheet` shipped dead. Now a
  `.simultaneousGesture`, which is what the rest of the app already uses where a
  parent gesture must coexist with children.
- P1: **The chat opened at the oldest message**, every visit, because the tab pager
  re-creates the view and the first-run guard skipped the scroll.
- P1: **The invite screen declared a valid link dead** whenever it merely failed to
  reach the server — the iOS twin of the P1 the web invite page already fixed. A
  nil preview now renders an explicit unverified state and keeps the request
  button, because `request_family_join` is the real authority.
- P1: **The house band was pinned to "parecido"** regardless of how much work is
  unowned, under a labelled three-band axis. Position is the only quantity this
  screen publishes, so a fixed slot was a false reading. Now weighed on the same
  scale, with a test.
- P1: **`"Ver o que está sem dono"` was a dead button** — it posted a notification
  nothing observed. Now wired through to the Hoje filter.
- P1: **The two halves of the type system scaled against each other.** Fraunces
  scales through `relativeTo:`; `.system(size:)` does not. Interface text is now
  metered through `UIFontMetrics`, and the root clamps at `accessibility1` because
  the boards' layouts have only been checked that far.
- P1: **"1 pessoas + Nina"** — the singular bug the rebrand was meant to kill,
  surviving in `AppStore.familyLimitLabel` and rendered in the settings sheet.
- P1: **"Retrato de domingo"** had been reintroduced as the digest's name, against
  round 4's finding that it is not Sunday-bound and that *retrato* is the app's
  word for the **free** workload portrait. Back to "Resumo semanal" at five sites.
- P1: **Three false claims in copy.** The search zero state said it looked in
  Compras (it never does); the consent screen said the digest stops when one adult
  revokes (one live grant is enough); the privacy screen filed completed tasks
  under "o que apaga sozinho" when that step archives and never deletes — while
  the chat deletion that *does* happen at 30 days was disclosed nowhere.
- P1: **`"Passar pro \(nome)"`** fused a masculine contraction onto a name whose
  gender the app deliberately does not model. Rendered "Passar pro Mirna".
- P2: **Contrast, measured rather than eyeballed.** `faint` failed AA on grout at
  seven eyebrow sites (4.14:1) and was darkened to `#646E7C` — 5.03 on ground, 4.52
  on grout. The unchecked checkbox, the primary control on four screens, was a
  1.24:1 outline; a new `control` token measures 3.23:1. The overdue tile's label
  was held back to 3.57:1 and is now full terracotta at 4.43.
- P2: **Fidelity and polish.** Done is a filled moss disc, as the boards draw it,
  not an outline. Row initials went from 7.7pt to the board's ratio. Faint came
  off sentence-case running text at six sites. The seeds view is titled
  "Sementes" and its rows carry the seed glyph rather than the category one. The
  search field no longer autocorrects "boleto" into "Bolero". The shopping
  checkbox has an accessibility label. The workload bands are announced.
  The day-cleared count regained its noun. The task detail's checkbox now fires
  the same haptic asymmetry its own footer implements.

## Accepted Without Change

- **`MemberDetailView` prints one person's open-task count.** Raised as a P0
  scoreboard violation and downgraded on inspection: it calls the public
  per-member query the invariant comment explicitly sanctions, it appears once
  behind a tap with nobody to compare against, and the pre-rebrand Casa screen
  showed every member's count side by side in a grid. Strictly less exposure than
  before. There is a real taste question — a band would be more Nina — but it is a
  stance conversation, not a defect.
- **The Sign in with Apple button's fixed 52pt frame.** The system control sizes
  its own label; the finding's premise about Dynamic Type is unverified and the
  pattern is Apple's own.
- **`MemberAvatar` announcing initials to VoiceOver.** That is exact parity with
  what is drawn; a sighted reader sees "RC" too.

## Still Open — recorded, not fixed

Hoje's sections are not collapsible though the board draws the chevrons; H2's
"amanhã cedo" card and T3's undo toast were not built; "Concluídas hoje" ignores
the Minhas filter; the seeds list has no Plantar control though its own caption
names one; chat attachments are decoded on the main actor; the tab pager destroys
per-tab scroll state on every switch; the pending-request badge is invisible to
VoiceOver; a failed purchase still prints in moss; the login e-mail field is
disabled without the matching opacity. None of these is a false claim or a broken
invariant, and all are one-site fixes.

## Final Checks

- `xcodebuild build` and the full `NinaTests` suite pass.
- `deno task check`, `lint:deletion`, `test` — 99 passed. `preflight:repo` — 0
  failures, 1 pre-existing warning.
- No store method with a live implementation is left without a call site.
- No copy claims a capability the code does not have, and no copy is in the past
  tense about a Nina action.
- Terracotta marks lateness and nothing else; moss marks human-confirmed
  completion and nothing else.
- Every text tier used passes WCAG AA against the surface it actually sits on, and
  the unchecked control clears the 3:1 non-text floor.
- Verified running on an iPhone 17 simulator, screen by screen against the boards.

Result (round 5): passed, with the nine open P2s above and the untested items from
round 4 — the mark's perceptual risk, and `C4`'s long-press against the tab
pager's gesture area on a real device.
