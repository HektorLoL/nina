---
target: web/src/pages/index.astro
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-08-14T17-35-52Z
slug: web-src-pages-index-astro
---
Method: dual-agent (A: design review, isolated · B: detector + browser evidence, isolated)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | A failed submit and a pending submit differ only by `font-weight: 600` at 14px; the menu button never changes state; focus is invisible on every conversion control. |
| 2 | Match System / Real World | 4 | The strongest thing on the page. *Vacina do Bidu*, *IPVA do carro*, *o comunicado que veio na mochila*, *A casa, por enquanto*. Nothing reads translated. |
| 3 | User Control and Freedom | 2 | Mobile menu closes on neither Escape nor outside tap; no back-to-top on a 7,082px mobile page; no path onto the list without opting into marketing. |
| 4 | Consistency and Standards | 3 | Palette rules held with unusual rigour. Two breaks: the mark is ink in step 2 (demoted to a peer of the category pictograms), and the cobalt check marks paywall constraints as if they were inclusions. |
| 5 | Error Prevention | 2 | Honeypot and `reportValidity()` are right. The biggest preventable error is conceptual: nothing stops a visitor clicking "Quero conhecer a Nina" believing they will get an app. |
| 6 | Recognition Rather Than Recall | 2 | "Nina Premium" named 3x, defined 0x, priced 0x. "Semente" is introduced only inside a note that is `display:none` on mobile. Nav says "O que a Nina faz"; the section says "Da bagunça mental para a rotina leve." |
| 7 | Flexibility and Efficiency | 2 | Scored, not n/a: skip link, `#lista` deep-link, four CTA entry points, anchor nav. Loses points because `.header-cta` is hidden below 980px, leaving ~6 mobile screens with zero conversion affordance. |
| 8 | Aesthetic and Minimalist Design | 3 | Stroked tiles, no shadows, one hue, drawn device. Genuinely restrained. Loses points for 493px of void inside the FAQ tile and three cobalt fills competing in the hero viewport. |
| 9 | Error Recovery | 2 | Good pt-BR wording, near-invisible rendering: 14px centred caption distinguished from the neutral status only by weight, and it reflows the dialog when it wraps. |
| 10 | Help and Documentation | 3 | Five FAQ items answering real objections. But the one fact a pre-launch visitor most needs is buried in the fifth collapsed item, and "Nina Premium" has no entry. |
| **Total** | | **25/40** | **Acceptable — significant improvements needed** |

## Design Specificity Verdict

**Authored content inside a borrowed chassis.**

**Unforgeable.** The drawn proposal card is the page's whole argument as an object: it labels itself `ISTO AINDA NÃO EXISTE`, offers *Confirmar · Corrigir · Ignorar*, sets `Dono: A casa, por enquanto`, and sits under Nina admitting her reading is fallible. It makes an unfalsifiable claim falsifiable on sight — you can *see* the thing not existing yet. The motion is engineered to refuse resolution, because the settled/moss state is licensed only by a human confirming and nobody on a marketing page has. The workload portrait is three qualitative bands under a headline that is three negations. Colour scarcity is auditable by eye: six cobalt fills page-wide, four terracotta elements (all lateness), four moss (all human-confirmed).

**Category-interchangeable.** The skeleton is a 2024 SaaS template: sticky header → split hero with phone + three floating notification cards → centered three steps → split feature-list-with-checkmarks → split feature + chart → dark panel beside FAQ accordion → wash-tinted CTA band → three-column footer. The `eyebrow → H2 → lede → cobalt check-list` stack repeats three times identically; nothing structural distinguishes the product section from the workload section. The three floating notes are the most generic element on the page — monochrome now, compositionally untouched.

**The sharpest observation:** the product's one idea is that a human confirms. The only thing a visitor can actually do on this page is open a modal and type an email. The `Confirmar` button in the hero is a drawing. The page proves its thesis in its artifacts and abandons it in its interaction model.

**Deterministic scan.** Markup-only pass across all five pages, the layout and the components: **exit 0, zero findings**. Including the stylesheet: **one finding** — `overused-font` at `global.css:6` (Fraunces). That is a false positive here; both faces are pinned by the brief, and byte-identical letterforms across app and web are a documented requirement. The scanning agent validated the clean result rather than trusting it — confirmed `.astro` is a scannable extension, ran a deliberately ugly fixture through the detector to prove the engine fires, and confirmed nothing was suppressed by config or inline comments.

**Visual overlays: not available.** No user-visible overlay exists. The site's CSP (`script-src 'self'`) blocks both an inline `<script>` and a cross-origin `<script src>`, so the overlay flow was impossible, not merely inconvenient. The live server was never started. Fallback was direct measurement in the page, which does work.

## Overall Impression

This page is unusually honest about the product and unusually careless about the visitor. The artifacts are the best work here — the proposal card, the three-band chart, the ink privacy tile — and they carry ideas no competitor could copy without adopting the whole product model. But the page's own promise is that nothing happens until a human confirms, and the page never lets anyone confirm anything. It asks for an email instead, behind a checkbox that bundles marketing consent with policy acknowledgement, on a surface whose entire differentiation is data honesty.

The single biggest opportunity is the one the motion system is already built for: **let the visitor tap `Confirmar` on the hero's proposal.** The sequence deliberately withholds the moss/settled state because nobody has confirmed. Give them the confirmation and the page stops describing the thesis and starts performing it.

## What's Working

1. **The drawn proposal card.** `ISTO AINDA NÃO EXISTE` / `Confirmar · Corrigir · Ignorar` / `Dono: A casa, por enquanto`. It works because it converts "nada entra na casa sozinho" from a promise into something you can check by looking. It is also why drawing the phone was right rather than screenshotting it: at 320px a screenshot of this card would be texture.

2. **Motion that enforces the product's grammar instead of describing it.** No resolution, because resolution requires a human. Combined with the inverted reveal pattern — resting page is the finished frame, the class *adds* the animation — no-JS, old browsers and reduced-motion readers lose nothing. Independently verified: with the chart 2,260px below the fold and `scrollY === 0`, the bands already compute cobalt without any script.

3. **Colour scarcity you can audit.** Every measured pair passes WCAG AA, with no failures: muted body 5.66, cobalt eyebrow 6.48 on ground and 5.82 on grout, faint 5.03, ink-panel body 8.74, primary button 6.65. In a category where hue-as-taxonomy is universal, refusing it is what buys the workload chart the right to exist without looking like a scoreboard.

## Priority Issues

### [P0] Focus is invisible on all five conversion controls
**What.** `.button-primary:focus-visible` and `.button-ink:focus-visible` set `outline-color: var(--ground)` at `outline-offset: 3px` — a `#FBFCFD` ring drawn outside the button, on the page's own `#FBFCFD` ground. Measured live: computed `outline: 2px solid rgb(251,252,253)`, contrast **1.00:1**, no visible change.
**Why it matters.** It hits the hero CTA, the header CTA, the mobile-menu CTA, the final CTA and the waitlist submit — every conversion control and nothing else. WCAG 2.4.7 / 2.4.11 failure at the exact points where it costs most. The comment above the rule ("A cobalt ring on a cobalt button is not a ring") shows the problem was seen; the fix moved the invisibility from inside the button to outside it.
**Fix.** `outline: 2px solid var(--ink); outline-offset: 3px; box-shadow: 0 0 0 3px var(--ground);` — a two-tone ring that reads on both the button and the ground.
**Suggested command:** `/impeccable audit`

### [P0] The page promises an app that does not exist, and only admits it after the click
**What.** The closing headline is *"A Nina já está esperando a sua mensagem."* All four buttons say "Quero conhecer". The hero footnote lists platform, language and data residency but never availability. The only honest statement — *"A primeira versão está sendo preparada para iPhone"* — is inside the fifth collapsed FAQ item at the bottom of a 7,082px mobile page.
**Why it matters.** The operating manual makes copy claiming Nina *acted* a defect. Copy claiming Nina *is waiting for you* is the same defect one tense over, on the one surface where a stranger decides whether to trust this product with a photographed boleto. It is also a peak-end failure: the warmest sentence on the page is answered by the coldest interaction, an administrative email form.
**Fix.** Put availability in the hero footnote (`iPhone · em preparação · entre na lista dos primeiros convites`), rename the CTAs to the outcome (`Entrar na lista de espera`), and rewrite the closing headline true in the pre-launch tense.
**Suggested command:** `/impeccable clarify`

### [P1] The waitlist bundles marketing consent with policy acknowledgement into one required checkbox
**What.** *"Quero receber novidades da Nina por email. Posso cancelar quando quiser e li a Política de Privacidade."* is a single `required` input. There is no way to join without opting into marketing. The dialog also carries zero reassurance: no frequency, no "sem spam", no restatement of the São Paulo residency the hero footnote promised, no company name.
**Why it matters.** This is the page's one dark pattern and it sits on the surface whose whole differentiation is data honesty, in the jurisdiction the product exists to serve. It is the highest-anxiety moment on the page and the only one with no supporting evidence.
**Fix.** Split into a required *"Li a Política de Privacidade"* and an optional *"Quero receber novidades"*. Add one reassurance line under the email field — the page already owns the sentence: *"Seus dados ficam em servidores em São Paulo. Um email só, quando estiver pronto."*
**Suggested command:** `/impeccable harden`

### [P1] The thesis sentence is the smallest type on the page
**What.** `ISTO AINDA NÃO EXISTE` renders at **7.40px**; `Confirmar e criar 1 tarefa` at **10.37px**; the gallery section labels at **7.22px**. The decorative floating notes beside them are 14px. Both assessments landed on this from opposite directions: the reviewer as a hierarchy failure, the scanner as 50 sub-12px elements.
**Why it matters.** The two elements carrying "Nina propõe, você confirma" are below the legibility floor while decoration sits above it. `role="img"` correctly rescues screen readers — that part is not a defect — but nobody else. The page whispers its argument and states its decoration.
**Fix.** Promote the claim out of the mockup: one interface-type caption directly under the phone at readable size (*"Nada existe até você tocar em confirmar."*), and let the drawn card stay purely illustrative. Do not raise the mockup type — that would break the device proportions.
**Suggested command:** `/impeccable typeset`

### [P2] The workload portrait is invisible to assistive technology, and its axis is ambiguous
**What.** `.workload-card` carries `aria-label="Exemplo do retrato de carga da casa"` on a `<div>` with **no `role`**, so the label is dropped — a screen reader gets three names and nine empty boxes. Both assessments found this independently. The two phone mockups two sections up do it correctly with `role="img"`. Separately, `A casa — sem dono` is drawn on the same *leve / parecido / mais pesado* scale as the two people, so unassigned work reads as "the house is carrying a light load".
**Why it matters.** This chart's entire meaning lives in which band is cobalt. Dropped label plus empty boxes means the section's argument does not exist for AT users — on the feature the product considers its most sensitive.
**Fix.** Add `role="img"` to the card and extend the existing label to describe all three positions. Give the house row its own visual treatment or its own axis label so it is not read on the carriers' scale.
**Suggested command:** `/impeccable audit`

## Persona Red Flags

**Jordan (confused first-timer)** — Clicks "Quero conhecer a Nina" expecting the app, gets an email form; the label names an intent, not an outcome. "Nina Premium" appears twice in feature lists with no price, no definition, no link, so Jordan cannot tell whether boleto reading is included. The three floating notes introduce *Ideia solta*, *Lembrete* and *Semente* as if already known — and *Semente* is defined only two screens down, inside a drawn phone, at 7.22px. Header nav "O que a Nina faz" lands on a section headed "Da bagunça mental para a rotina leve", so arrival is never confirmed. On mobile the floating notes are `display:none`, so that vocabulary never arrives at all.

**Riley (deliberate stress tester)** — Tabs from the top and the hero CTA shows no focus ring; same for three more controls. Opens the mobile menu, presses Escape: nothing. Taps outside: nothing. The hamburger never becomes an ×. Reads the consent checkbox and finds marketing bundled into a required control. Forces a network failure and gets a 14px ink caption almost identical to the neutral "Enviando com segurança" — while the design system already ships `.status-dot.error` for the invite page and does not use it here. Reads "A Nina já está esperando a sua mensagem", then finds the contradiction in the last collapsed FAQ item. Screen-reads the workload chart and gets three names and nine empty boxes. Notes the page names no company, no CNPJ and no address, then asks for an email and shows photographed boletos.

**Casey (distracted mobile user)** — The hero lede is five lines of centred body copy, ragged on both edges at 17px, on the page's most-read paragraph. The page is 7,082px tall at 375px (8.7 screens) with no sticky CTA, leaving roughly six screens between the hero button and the footer button with zero conversion affordance. The phone gallery is a 690px snap scroller inside a 297px box whose only affordance is a 39px sliver of the second device — no dots, no counter, no cue — so Casey scrolls past vertically and never sees the Tarefas screen. Opening the waitlist focuses the *optional* first-name field, raising the keyboard immediately and pushing the consent checkbox and submit below it. That checkbox is 20x20, under WCAG 2.2's 24x24 minimum. Six links are under 44x44, the three footer legal links at 21.7px tall.

## Minor Observations

- **The FAQ tile is 52% empty on desktop.** Measured 609x947 with a 503x302 list — 493px of bare ground inside a stroked tile, arriving immediately before the close, reading as the page running out of argument at the moment it should be closing. `align-items: start` on `.support-grid` fixes it; filling it with the missing Premium and availability answers fixes it better.
- **`.note-two` overlaps the proposal card by 29px** at 1440, clipping the right border of the single most important artifact in the hero.
- **The one authored motion moment is usually missed.** The hero is fully visible at 1440x900, so the ritual arms at load and finishes before most readers finish the H1 and lede — and for the first ~420ms the hero's product visual is an empty phone.
- **The mark is ink in step 2**, where it also sits as a peer of the chat and people pictograms — the identity mark demoted to a category glyph.
- **Cobalt does four jobs** (brand, commit, active chip, band position) and three of the six page-wide fills sit in the hero viewport, diluting the one that is actually clickable.
- **The cobalt check marks constraints as inclusions**: "✓ Lê boleto… no Nina Premium" and "✓ O retrato faz parte do Nina Premium" read as included when they mean the opposite.
- `.speech` has a bottom-left tail pointing at nothing, and is not centred in the mobile band.
- `.step-arrow` at `--line` measures 1.24:1 and is effectively invisible, so the three steps read as three cards rather than a sequence.
- The product section gives the copy 366px and the illustration 660px; the H2 wraps to three lines.
- Section labelling is inconsistent: the hero and the FAQ use `aria-labelledby`; the product, workload and privacy sections do not.
- **Verified clean:** zero horizontal overflow at both widths, zero console messages on a fresh load, no heading-order skips, no `<img>` without alt (there are no `<img>` at all), all 41 SVGs correctly `aria-hidden`, every control has an accessible name, and no text actually truncates despite 21 elements carrying `text-overflow: ellipsis`.

## Questions to Consider

1. **The product's one idea is that a human confirms — and the only thing a visitor can do here is type an email.** Why is there not one real confirmation? Let them tap `Confirmar` on the hero's proposal, watch the disc settle and take moss, and read *"Isso é tudo que a Nina faz."* The motion is already authored to withhold that state. Letting someone earn it converts the page's strongest asset from a picture into an experience — and it is the one move a competitor cannot copy without adopting the entire product model.
2. **If terracotta is lateness only and moss is human-confirmed only, what colour is a failed submission allowed to be** — and is `font-weight: 600` an answer or an unfilled gap? The system already ships an ink error dot for the invite page.
3. **"Nina Premium" is named three times, priced zero times, linked nowhere.** Is the paywall being disclosed or advertised? `R$ 24,90/mês` is a number the product knows.
4. **Is the document story the hook or the risk?** It is simultaneously the most concrete capability on the page, the most gated, and the most legally exposed — and the footer names no legal entity.
5. **"Sem porcentagem. Sem placar. Sem ganhador." — and then the chart puts one named person at the far right of a shared left-to-right scale.** Position is an ordinal encoding whether or not a number sits on it, and the caption arrives after the reader has already ranked Mirna and Rafa. Does the disclaimer survive the picture?
6. **The floating notes are `display:none` below 1080px.** On an iPhone-only product, the iPhone visitor is the one who never sees the three artifact types the desktop hero teaches. Which viewport is this page actually for?
