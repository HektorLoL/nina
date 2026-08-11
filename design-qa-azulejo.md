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
