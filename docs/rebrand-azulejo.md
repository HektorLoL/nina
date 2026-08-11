# Nina — rebrand "Azulejo"

Last updated: 2026-08-10

Design direction and full flow proposal, derived from `task-app-design-teardown`
(74 screens / 41 products) and `nina-pattern-mapping` (156 patterns mapped to
Nina's shipping build).

Paper file: https://app.paper.design/file/01KZP8YB2108T0W8ZQSA9YGP9W/1-0

**Build status.** Ten bands, 37 boards, all on the `Design principles` page.
Section 3 records the spec each was built from, plus the three places the build
knowingly departs from that spec. The QA verdict is in `design-qa-azulejo.md`.

Bands 8–10 cover what the pattern mapping listed under "what this mapping did
not cover": the Tarefas tab, the document path, the privacy tree, every failure
state, and the surfaces where Nina speaks outside the app.

---

## 1. The direction

**Mood: azulejo** — the fired tin-glaze tile of a Brazilian kitchen wall.
Brazilian without carnival; a domestic scene; literally the wall of the room
where the mental load lives.

It also fixes a mechanical problem. Today's app is a warm cream ground plus mint
plus five more hues, and the audit's verdict is that *six categories exhaust a
five-tone palette, so a Saúde task is coral like an overdue one*. A warm tinted
ground mutes chroma, which is why every hue had to be pushed until they all
shouted. A cool glaze ground restores the headroom so one colour can carry
consequence.

### Palette

| Token | Hex | Object in the scene | Rule |
|---|---|---|---|
| `--color-ground` | `#FBFCFD` | fired tin glaze | every screen background |
| `--color-grout` | `#EDF0F4` | line between tiles | fields, inactive chips |
| `--color-line` | `#DFE4EB` | — | hairlines, card strokes |
| `--color-ink` | `#131A24` | painter's cobalt-black outline | primary text |
| `--color-muted` | `#5C6675` | grout in shadow | secondary text, min 13px |
| `--color-faint` | `#6A7482` | — | tertiary; 12px floor, uppercase labels only |
| `--color-cobalt` | `#1B4FD8` | the pigment | brand, Nina, commit. **One moment per screen** |
| `--color-cobalt-wash` | `#E6EDFC` | where the brush ran thin | Nina's bubbles, selected chips |
| `--color-terracotta` | `#C2410C` | unglazed clay under a chipped tile | **overdue only** |
| `--color-terracotta-wash` | `#FBEAE1` | — | overdue block ground |
| `--color-moss` | `#3F6B4A` | courtyard fern | confirmed / done, tiny use |

### Type

Fraunces (display 400) × Inter (UI 400–700). Scale 44 / 34 / 27 / 22 / 17 / 15 / 13 / 11.

Fraunces appears only in screen titles, Nina's own voice, and the single big
number. Never in a list row.

### The structural rule

**Category is a glyph. Never a colour.** Seven monochrome 20px glyphs: Casa,
Contas, Saúde, Escola, Pet, Comida, **Cuidado**.

`Cuidado` is new. The current six are a taxonomy of household *logistics* —
there is no category for the labour the product most wants to make visible.
Cuidado names remembering, scheduling, following up, asking: the invisible load.
This is Tiimo's "taxonomy is positioning" move applied to Nina's actual thesis.

---

## 2. The 25 boards

| Board | What it establishes |
|---|---|
| `00 · Fundação` | palette, type scale, glyph set, the category-is-a-glyph rule |
| `O1 · Descarregue` | capture on screen one, no account — Numo's move |
| `O2 · O ritual` | the confirmation grammar, all 8 rules at once |
| `O3 · Personalizar tirando` | Angi's subtraction, quantified |
| `O4 · Três perguntas` | Tiimo's questions in the user's words |
| `O5 · Quem mora aqui` | household, "Nina não ocupa vaga", invite-message preview |
| `O6 · Conta por último` | identity deferred to the end |
| `O7 · Convite é a primeira tela` | the invite-first entry path |
| `H1 · Hoje` | main page rebuilt — first task row at ~350px, was ~780px |
| `H2 · Hoje no zero` | empty state that congratulates and grants permission to stop |
| `C1 · Captura` | title focused, chips above the keyboard, Tipo after the title |
| `C2 · Captura de semente` | the date chip visibly disables — the primitive taught in place |
| `C3 · Detalhe da tarefa` | the screen that does not exist today, with provenance |
| `C4 · Ações rápidas` | long-press sheet, the swipe substitute |
| `N1 · Conversa` | the launch tab, with the tappable load strip |
| `N2 · Proposta de memória` | Corrigir plus two visibility exits, sharing named irreversible |
| `N3 · Duas propostas` | a Semente proposed, and a date refused rather than invented |
| `N4 · Negação de premium` | a server denial that routes, instead of dead-ending |
| `S1 · Retrato inconclusivo` | the refusal rendered honestly — **no chart at all** |
| `S2 · Retrato conclusivo` | three-band axis, household order, no number anywhere |
| `S3 · Casa` | roles, slots with a singular branch, invite preview |
| `S4 · Memórias no zero` | the privacy invariant moved to where it does its work |
| `G1 · Compras` | aisle sections, square boxes, positional stability, household nudge |
| `P1 · Paywall` | ✗ column, named ceilings, CTA hierarchy corrected |
| `V1 · Estados vazios` | six zero states, each doing one of the three jobs |
| `T1 · Tarefas` | the fourth tab, never drawn before; all sections stacked, not one-at-a-time |
| `T2 · Sementes` | the third primitive gets its own surface |
| `T3 · Concluir sem pressa` | the 3-second reversible completion and its haptic asymmetry |
| `D1 · Documento lido` | the sensitive path's success state — what Nina read, and what is not kept |
| `D2 · Consentimento de IA` | the LGPD gate, per adult, with a real decline path |
| `D3 · Privacidade e dados` | export, retention, revocation, where the data lives |
| `D4 · Apagar a conta` | the destructive confirm that names what remains |
| `E1 · Conflito de edição` | both versions shown; no dismissal, because dismissal used to mean remote-wins |
| `E2 · Sem internet` | the error the app currently buzzes for and never displays |
| `E3 · Esperando aprovação` | the waiting room, told it will be notified rather than polled |
| `W1 · Notificações` | Nina's voice on the lock screen, and what never reaches it |
| `W2 · Widget` | the three widget families at their real fixed sizes |

### W1 and W2 were rebuilt against real iOS

The first versions were not buildable. Three things were wrong, found by looking
at shipping widgets and lock screens on Mobbin rather than reasoning from memory:

- **The widget was one invented size.** iOS widgets come in fixed families and
  you do not get to choose a shape: `systemSmall` 155×155, `systemMedium`
  330×155, `systemLarge` 330×346. The board now shows all three at those exact
  proportions, and the interesting design work is what survives the shrink — the
  large one lists five rows with an overdue block, the medium keeps three rows,
  the small keeps a single number and the overdue count. Reference:
  [Todoist](https://mobbin.com/screens/e3664e12-9fd4-4240-aca2-522f44003b9e),
  [Tiimo](https://mobbin.com/screens/328f199c-2624-429a-aa4f-60ebf1ada74d) and
  [Abode](https://mobbin.com/screens/3dd68d11-1906-459e-a6fa-6fd7f1d629f3) all
  present exactly this family stack on a neutral ground.
- **The lock screen had no lock screen.** No date line, no flashlight or camera
  buttons, no correct clock weight. Notifications also sit low on the screen
  above those buttons, not floating under the clock. Reference:
  [Transit](https://mobbin.com/screens/b84f786b-1c21-4110-9977-f0544d9adcf5) and
  [Tide Guide](https://mobbin.com/screens/45be33cf-6385-4455-a699-7a4c55e5511a).
- **A design-rationale card was rendered inside the phone as product UI** — the
  same defect the QA pass caught on `O7` and I repeated here. Both boards are now
  pure screens. The rules those cards carried live here instead:

**What Nina says outside the app.** She speaks as a person, never a hyphen-joined
field dump. The task's detail never reaches the lock screen or a widget — it may
be a boleto or a prescription. Quiet hours remove the sound and never move the
delivery time, because showing one time and delivering at another would be a lie.
The widget reports how much is on you, never what it is: whoever passes your desk
can read it.

### O2 in detail — the eight AI grammar rules on one card

This is the screen everything else rests on.

1. **Restate** — "Li assim. Se eu entendi errado alguma coisa, corrija antes de confirmar."
2. **Render the real object** — the card is a task row, with the same checkbox and glyph.
3. **Count in the CTA** — "Confirmar e criar 1 tarefa".
4. **Three exits** — Confirmar / Corrigir / Ignorar.
5. **Name the blocked state** — "A Nina está esperando você." written into the thread.
6. **Provenance** — the card sits under the message, tagged `ISTO AINDA NÃO EXISTE`.
7. **No coerced consent** — no reply chips at all; disagreement is a first-class button.
8. **Never past tense** — nowhere on the screen.

Plus the accuracy disclaimer the audit found absent (`R9`): *"A Nina pode ler
errado. Ela nunca cria, altera ou apaga nada sozinha — nada acontece até você
tocar em confirmar."*

**Decisive fields are on the card face, not behind Corrigir.** Quando, Repete,
Responsável render as labelled rows. Today they are hidden behind the edit
toggle, so the user confirms a date they never saw.

---

## 3. Band specs, and where the build departed from them

One band per row, 390×844, pitch 470px horizontal / 1040px vertical.

Three departures, all deliberate:

- **`C2` became "Captura de semente" rather than a date-correction sheet.** The
  date-correction point is already carried by `O2`'s Quando field; showing the
  date chip *disabling itself* when Tipo flips to Semente teaches a product
  primitive that has no other home.
- **`G2` (household nudge) and `G3` (shopping mode) were folded into `G1`.** Both
  are visible on that one board — the nudge banner at the top, the
  Montar/Comprar switch in the header. They did not need their own artboards, and
  splitting them would have hidden that they coexist.
- **The workload boards moved from bars to bands.** The spec said "replace ranked
  bars with a three-band axis"; the built version drops the track-and-marker idea
  entirely for three equal segments, which removes the last thing a reader could
  measure one person against another with.

### Band 3 — Captura e o objeto tarefa (y = 3200)

**C1 · Captura.** The single most convergent interaction in the category, and
the one Nina inverts hardest today.

- Sheet rises from the bottom, radius 28 top corners.
- **Title field focused on open**, keyboard already up. Reuse the keyboard group
  built on `O1` via `x-paper-clone`.
- Placeholder: `O que precisa ser feito?`
- **Chip row directly above the keyboard**, horizontal scroll, chips carry
  *resolved values*, not field names:
  `Hoje` · `Ninguém ainda` · `Casa` · `Não repete` · `Sem valor`
  Unset chips show the label in `--color-muted` with a 1px line border. Set chips
  fill `--color-cobalt-wash` with `--color-cobalt` text and 600 weight.
- **Tipo comes after the title, and is a chip, not a segmented control.** Today
  it is the first card in the scroll — the user's first required act is a
  taxonomy decision about an intention they have not yet written down.
  New: one chip reading `Tarefa` that toggles to `Semente` and, when toggled,
  dims and disables the `Hoje` date chip with the line
  *"Semente não tem data. É isso mesmo."*
- ✕ top-left, filled cobalt ⌃ circle bottom-right near the thumb.
- Nothing required but the title.

**C2 · Captura com correção.** The same sheet after tapping the `Hoje` chip —
inline date sheet, showing that a corrected label recomputes the scheduled date.
Caption on the board: *a label change must move `dueAt`, or the confirmation
ritual is decorative.*

**C3 · Detalhe da tarefa.** The screen that does not exist today — `RouterPath.navigate(to:)`
has zero call sites, so tapping a task opens an edit form even for a viewer who
cannot edit.

Fixed vertical stack, one scroll, in this order:
1. Title at 27px Fraunces, glyph inline at the right.
2. Metadata rows — Quando · Repete · Responsável · Categoria — same lane geometry
   as the proposal card, 96px label column.
3. **Provenance line**: `Adicionada pelo Rafa · sexta, 7 de agosto`.
   `createdBy` is captured on every task today and rendered nowhere reachable.
   In a shared household this is what stops "why is this here?" becoming a
   conversation.
4. Action chip row: `Remarcar` · `Passar para alguém` · `Virar semente` · `Apagar`.
5. Comments — reactions before comments. Press-and-hold reaction row
   (Google Maps' pattern), plus one `Deixar um recado` field. Not a thread.
   Lower ceremony, and it cannot turn into an argument thread.
6. Composer pinned to the bottom.

**C4 · Ações rápidas (long-press).** Nina has zero swipe actions app-wide by
architectural necessity — the horizontal drag belongs to the custom tab pager.
Substitute: long-press a row opens a compact action sheet with
`Feito` · `Amanhã` · `Passar para o Rafa` · `Virar semente`.
Flagged deviation, see §4.

### Band 4 — Nina e o hand-off (y = 4240)

**N1 · Conversa.** The chat tab, which is the app's launch tab.
- Top strip: one tappable line `6 na sua mão · 2 atrasadas` so the "what is on me"
  question is answered in under two seconds without abandoning the chat-first thesis.
- Thread, Nina in `--color-cobalt-wash` bubbles with a 24px cobalt dot avatar.
- Composer with a `Documentos` chip carrying a small lock when the household is
  not premium — the one pre-emptive gate affordance that already works today.
- Empty state uses the copy the audit called the best capture beat in the app:
  *"Jogue uma lembrança aqui"* with four household utterances.

**N2 · Proposta de memória.** The highest-stakes proposal type, and today the one
with no edit path.
- Same card grammar as `O2`, plus **Corrigir**.
- Two visibility buttons, never one accept:
  `Guardar para mim` (default, cobalt) and `Compartilhar com a casa` (outline).
- Sharing a private memory is the most irreversible act in the product and has no
  confirm today. Add one, and name what remains:
  *"O Rafa vai poder ler isto. Não dá para voltar a ser só sua."*

**N3 · Proposta múltipla + recusa.** Three proposal cards stacked, the count in
each CTA, and one Nina line refusing to invent a date:
*"Você não disse quando. Deixei sem data — dá para plantar como semente."*
Demonstrates that Sementes are proposable, which they are not today: the proposal
`kind` CHECK omits `'seed'`, so one of three product primitives is unreachable
from the AI.

**N4 · Negação de premium com rota.** A server denial (`nina_attachments_require_premium`,
quota, digest) rendered as a Nina line **with a button to the paywall**. Today it
is a plain chat line with no route.

### Band 5 — Sinal de sobrecarga e Casa (y = 5280)

**S1 · Retrato inconclusivo.** The refusal, rendered honestly.
- Headline `Ainda sem retrato da casa`, the existing message, **and no chart.**
- The single sharpest defect in the audit is that both render sites gate on
  `hasAnyLoad` rather than `isConclusive`, so the app says it cannot draw the
  division without guessing and then, eight points below, draws the guess.
- Add the promise copy that `hasAnyLoad` currently gates out of the true-zero case.

**S2 · Retrato conclusivo — banda, não barra.** The mirror drawn with the
mirror's grammar.
- Replace ranked bars + exact integers with a three-band qualitative axis:
  `leve` · `parecido` · `mais pesado`. No number anywhere on the chart.
- Rows in **household order, not sorted by count** — sorting by open count
  descending *is* a ranking, whatever the caption says.
- `A casa` drawn as its own muted band. Unassigned work is never credited to a person.
- Provenance line under the chart, stoic.'s move:
  *"Do que está em aberto agora, com responsável. Sementes não entram."*
- Caption stays: *"Um retrato para conversar, não para cobrar."*

**S3 · Casa.** Members, roles, invite.
- Member rows: avatar · name · relationship · crown glyph for owner.
- Nina's row carries `IA da casa · não ocupa vaga`.
- Slot counter with a singular branch — today it reads `1 pessoas + Nina`.
- Invite card reuses the WhatsApp message preview from `O5`.
- Tapping a member opens a **read-only detail** for viewers, the editor only for
  those who can edit. `MemberDetailSheet` is built and never constructed today.

**S4 · Memórias.** The zero state carries the privacy invariant:
*"Memórias pessoais começam privadas. Compartilhar com a casa é sempre uma
escolha explícita."* This is the best "teach an invariant" copy in the study and
it currently shows only inside a one-time consent gate — Superlist's exact move,
applied to copy Nina already owns.

### Band 6 — Compras (y = 6320)

Groceries are a different object with different physics, and Nina currently runs
task physics on them.

**G1 · Lista por seção da loja.**
- **Square checkboxes.** Circles for things with an owner and a moment, squares
  for stock. Nina uses one circle for tasks, seeds and groceries alike today.
- **Grouped by aisle**, not by time: `Hortifrúti` · `Padaria` · `Limpeza` ·
  `Frios` · `Outros`. Needs a `category` column; there is no aisle concept in
  Swift or Postgres today.
- **Checked items stay exactly where they are**, struck through in place.
  In an aisle you need positional stability. Today they reflow into a bottom
  bucket and `created_at desc` ordering reshuffles the list mid-trip.
- Quantity as a terse right-aligned string: `2 un` · `1 kg` · `500 g`.
- `Limpar comprados` as an end-of-trip sweep, not an automatic reflow.

**G2 · Aviso da casa.** The one household-aware pattern in the whole study, and
arguably the most on-thesis: a banner reading *"Indo ao mercado? Avise a casa
para adicionar."* with an `Avisar` action. Absent from Nina entirely.

**G3 · Modo compra.** Instacart's Planning/Shopping switch. Bigger rows, bigger
tap targets, section headers pinned. The same list has two jobs and the second
one happens standing in an aisle holding a phone in one hand.

### Band 7 — Premium e estados vazios (y = 7360)

**P1 · Paywall.** Every part of the current one is inverted.
- Segmented Mensal / Anual control **with the saving on the control itself** —
  `16% de economia` is authored in `Nina.storekit` and never rendered.
- Prices normalised: `R$ 20,82/mês` under the annual option.
- **Two-column table where the free column is a list of ✗**, naming the three
  real server-enforced ceilings:

  | | Grátis | Premium |
  |---|---|---|
  | Documentos e fotos | ✗ | ✓ |
  | Conversa com a Nina | 10 por dia | 30 por hora |
  | Retrato de domingo | ✗ | ✓ |

- One `Mais escolhido` badge.
- **CTA hierarchy corrected**: purchase is the full-width cobalt button,
  `Restaurar compras` is a text link. Today it is exactly backwards — the one
  screen in the app that breaks the app's own commit grammar.

**V1 · Estados vazios.** One board, six states, each doing one of the three jobs.

| Surface | Job | Copy |
|---|---|---|
| Hoje no zero | congratulate | `Acabou o dia da casa.` + `Pode largar o celular.` |
| Memórias | teach an invariant | `Memórias pessoais começam privadas.` |
| Sobrecarga | promise | `A Nina precisa de algumas tarefas com responsável para desenhar a divisão sem chutar.` |
| Filtro vazio | educate, don't create | text-only card, no ＋ button |
| Compras vazio | promise | `O que acabar em casa aparece aqui.` — **not** `Nenhuma tarefa encontrada`, which the shopping search state says verbatim today |
| Aprovação pendente | name the blocked state | `A Mirna ainda não respondeu. Você vai receber um aviso.` — today it is a manual-refresh waiting room with no polling and no push |

Also fix `PremiumBenefitsSheet`, which currently shows end users the operator
string `Configure os produtos Premium no App Store Connect`.

---

## 4. Deliberate deviations

Places where the benchmark says one thing and this design does another, on purpose.

| # | Pattern in the study | What Nina does | Why |
|---|---|---|---|
| 1 | Open on a temporal frame | Opens on the **chat tab**, not Hoje | The chat *is* the capture surface; that is the thesis. Mitigated: Hoje's counts strip is repeated at the top of the chat, tappable, so load is still legible in under two seconds. |
| 2 | Quantified progress (streak, ring, score) | **Three-band qualitative axis, no number** | stoic.'s fork, taken all the way. Nina keeps the number today and removes only the adjective, which is half a commitment. A quantified comparison between two people is a scoreboard whatever the caption says. |
| 3 | Sort the workload chart by load | **Household order, never ranked** | Row order is an encoding. Sorting descending *is* the ranking the caption disclaims. |
| 4 | Completion emits a message to the thread (Telegram) | **Refused at every layer** | The study's most interesting shared-list pattern and the wrong one here — surveillance dressed as visibility. No `completed_by` column exists and none should. |
| 5 | Suggested reply chips | **None at all** | Cleo's fix is chips that include "no". Structural refusal is stronger: with no rail, manufactured consent is impossible and disagreement is already a first-class button. |
| 6 | Categorical colour on rows (Numo, Tiimo) | **Monochrome glyph, colour reserved** | The direct cause of the current palette collapse. Colour is spent on lateness and nothing else. |
| 7 | Swipe actions on rows | **Long-press action sheet** | Architectural: the horizontal drag belongs to the custom tab pager. Not a preference. |
| 8 | Warm off-white × terracotta is a cliché to avoid | **Used anyway, at small size** | The ground here is a *cool* glaze white, not warm off-white, and chipped glaze revealing clay is the honest reference in this scene. Flagged because it is one step from a known trap. |
| 9 | Geometric sans, category-wide | **Fraunces serif display** | A serif reads as a letter from a person. This is "Sua amiga Nina", not a productivity dashboard. |
| 10 | Onboarding ends at an empty Today (Todoist) | Ends at a **populated** Hoje | Subtraction already produced four real tasks. Rewarding onboarding with an empty screen would waste the artefact the flow just built. |

---

## 5. Server-side changes this design assumes

Design decisions above that are not purely client work:

- `shopping_items` needs a `category` (aisle) column and a stable `sort_order`.
- `nina_proposals.kind` CHECK must accept `'seed'`, and `resolve_nina_proposal`
  must set `task_kind`, or Sementes stay unreachable from the AI.
- `nina_weekly_metrics` counts every non-done row with no `task_kind` filter, so
  **sementes count as open load in the weekly insight** — precisely what seeds
  exist not to be. Correctness bug, needs `task_kind = 'task'` on both queries.
- A `Cuidado` value added to the category CHECK.
- Sharing a memory needs a confirm step.

---

## 5b. Advertising — the `Advertisement` page

Seven boards on the file's second page, kept separate from the product boards.
Three web sections at 1440 and four App Store screenshots at 430×932 (6.7").
Patterns checked on Mobbin: the editorial statement-beside-a-real-screen from
[1Password](https://mobbin.com/sites/sections/60389765-0d29-4b2f-ac9c-2ce9986e4412),
and the caption-above-device-on-a-brand-panel convention every App Store listing
uses.

**`A2` exists to correct the site.** The landing page currently advertises
**82% / 48% / 64%** for the workload feature — three percentages for a product
whose entire stance is that there is no score, and which the redesigned portrait
now refuses to show at all. The mapping doc flagged this and it is still live at
`web/src/pages/index.astro:234,239,244`. The new section makes the absence the
headline: *"Sem porcentagem. Sem placar. Sem ganhador."* Shipping the rebrand
without this edit would leave the marketing site promising a number the app
deliberately withholds.

### What these boards promise that the build does not yet keep

Both `A1` and `B2` sell the confirmation ritual — Nina proposing and a human
confirming. **`NINA_AI_V2_ENABLED = NO` is the default**, so on the shipping
build every proposal is discarded before it reaches the UI: she can talk, she
cannot organise. The advertising is therefore written for the flag-on product.
Turning it on needs the one operational step in
`docs/production-launch-runbook.md` §3 — rejecting the outstanding pending
proposals server-side before the build ships.

Two further blockers, neither of them design work. `NINA_APP_APPLE_ID` is still a
placeholder, so the App Store screenshots have nowhere to be submitted. And the
legal identity is still `replace_with_…`, so no footer on these boards carries an
entity name, a CNPJ, or a DPO.

## 6. Next

The canvas is complete and the QA pass is recorded in `design-qa-azulejo.md`
(`Result: passed` — 79 findings raised, 27 refuted, 52 resolved, one of them a
P0). Two palette values changed as a result: `--color-faint` was darkened because
it failed WCAG AA at every size it was used, and the muted floor was relaxed from
15px to 13px because the measured contrast said the original rule was a
preference dressed as a limit.

What is left is not design work. The §5 server items still stand, two of them
correctness bugs rather than anything visual.

Two boards are worth revisiting before any of this reaches code. `C4`'s
long-press sheet has never been tested against the tab pager's gesture area, and
`S2`'s three-band encoding is the single least reversible choice in the rebrand —
it is the one thing here that should be put in front of a real couple before it
is built.
