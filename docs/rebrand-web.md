# Nina web — the azulejo pass

Last updated: 2026-08-14

The site was rebuilt onto the azulejo system on 2026-08-14, three days after the
iOS app. Sources: the `Advertisement` page of the Paper file (`A1` hero, `A2`
sinal de sobrecarga, `A3` documentos e privacidade), `docs/rebrand-azulejo.md`,
and the palette and geometry the app actually ships in `Nina/Theme.swift` and
`Nina/NinaMark.swift`.

**The brief was to keep the old structure and replace the aesthetic.** The
section sequence is unchanged — header, hero with a phone and three loose notes,
three steps, product with a three-phone gallery, the workload section, privacy
beside FAQ, closing CTA, footer, waitlist dialog. Every one of those is still
there, in that order. What changed is what they are made of.

---

## 1. What the system forced

- **Six hues became one.** `--mint`, `--coral`, `--sky`, `--amber` and
  `--lavender` and their five wash tints are gone. Cobalt is brand and commit,
  terracotta is lateness and nothing else, moss is confirmed-by-a-human and
  nothing else. Everything that used colour to encode a *kind* — the four eyebrow
  tones, the three step tones, the three floating-note tones, the per-person
  workload bars — is now monochrome plus a glyph.
- **Filled, shadowed, gradient panels became stroked tiles.** Sections alternate
  ground, grout and one ink tile, like a laid wall. There is one shadow left in
  the stylesheet: none.
- **Dark mode was deleted.** The azulejo palette is a fired tin glaze and has no
  designed dark counterpart, exactly as in the app. `color-scheme: light` is
  pinned and the two `theme-color` metas collapsed to one.
- **The cartoon face is gone everywhere.** `NinaMark.astro` transcribes both of
  the app's masters — the 64 grid above 34px, the 24 grid below — including the
  floor gap, which is the mark's critical dimension. It is never re-cropped into
  a circle or a badge; the old `border-radius: 50%` wrappers were removed rather
  than refilled.

## 2. Where the build departed from the boards

- **`A1`'s header still draws the pre-mark cobalt dot.** The advertising boards
  were built before band 11, so they carry the 11px puck that round 4 graded a P0
  on `S3` and `N1`. The site draws the real mark. This is round 4's own rule —
  a confirmed correction is a sweep across every surface — applied to the one
  page it had not reached.
- **The hero keeps the old three-line headline slot but loses its coloured
  accent line.** The old third line was mint. Colouring a headline line would
  spend the section's cobalt moment on type rather than on the commit control,
  so the headline is all ink and cobalt goes to the eyebrow and the CTA.
- **The rotated handwritten note under the hero CTA is gone.** The bundled
  Fraunces cut has no italic, and a faux-italic rotated sticker is the warm-cream
  register the rebrand replaced. Its slot survives as `A1`'s honest footnote.
- **`A3` is folded into the existing privacy panel rather than added as a fourth
  full-width section.** The brief was to preserve the section count. The ink
  tile carries `A3`'s three cards and its register; the site gains the document
  story without gaining a section.
- **`A3`'s third card no longer claims the model provider "não guarda nada do que
  recebe".** What the repository enforces is `store: false` on every call — a
  request, with no DPA behind it and no legal entity yet to sign one. The card
  says what is true: *"pede que ele não guarde o que recebe."* This is the open
  item round 4 recorded against `Nina/NinaChatView.swift:244`, and it is now
  resolved on the web side only.
- **The phones are drawn, not photographed.** The four `nina-*.jpg` screenshots
  showed the pre-rebuild app — a cream ground, a mint tab bar and the cartoon
  avatar — and were deleted. `A1` already draws its phone in markup for a reason:
  at 320px a screenshot of a proposal card is unreadable, and a drawing cannot go
  stale against the app it quotes. The gallery's three screens are drawn from the
  shipping `TodayView`, `TasksView` and `HouseView`. Both mockups are
  `role="img"` with a full description, because their type is illustrative and
  sits below the interface floor.

## 3. What the pass fixed on the way through

- **`npm audit --audit-level=high` was red and CI was failing it.** `astro-icon`
  pulls `@iconify/tools` → `extract-zip`, which carries GHSA-jmr9-qjv8-65gv.
  Dropping it removed three dependencies and the advisory. The site's ~20 glyphs
  are now hand-authored on the boards' own 24 grid in `Glyph.astro`, which also
  makes them outline rather than the filled Phosphor variants the system forbids.
- **The landing page advertised 82% / 48% / 64%** for a portrait the rebuilt app
  refuses to score — and the three figures summed to 194%, so they were not
  shares of anything even internally. Replaced by `A2`'s three-band chart, in
  household order, with `A casa — sem dono` as its own muted row.
- **Copy that claimed Nina acts.** "Tarefa criada", "A Nina organiza",
  "Distribui tarefas", "editar algo que a Nina criou" all read as past tense or
  as autonomous action. The three steps now end on *Você confirma*, which is the
  product's actual grammar.
- **Copy for features that do not exist.** The old page sold voice input and
  calendar integration. Neither is built.
- **Documents were sold as free.** Attachments are gated by
  `nina_attachments_require_premium` inside `begin_nina_chat_run`, so the feature
  list says so, the way `A2` says it about the portrait.
- **Without JavaScript the page rendered blank.** Every section carried
  `.reveal { opacity: 0 }` and the observer that clears it never ran. Patched
  here with a `<noscript>` stylesheet, then removed entirely by the motion pass
  below, which inverted the pattern so the resting page is already complete.
- **`prefers-reduced-motion` froze the invite spinner**, turning the one
  animation that reports state into a decoration that reports nothing.
- **The closed mobile menu still held keyboard focus** (`opacity: 0` alone), the
  focus ring was cobalt on cobalt buttons, form inputs had no boundary above the
  3:1 floor, and the legal pages hid their nav below 980px behind a menu button
  they do not have. All four fixed.
- **Every contrast pair was measured rather than eyeballed.** `--faint` ships at
  `#646E7C`, the app's value, not the board token `#6A7482`, which measures
  4.14:1 on grout and fails AA for body text there. `--control` `#848E9D` exists
  because `--line` is 1.24:1 and can decorate a card but must never be the only
  boundary of an input.

## 4. Motion

Added 2026-08-14, after the palette pass.

**One authored sequence, one teaching moment, and feedback.** The eight identical
section fade-and-rises were deleted: a wall does not assemble itself while you
look at it, and a repeated entrance is not a thesis.

- **The hero phone performs the ritual once**, about 3.2 seconds. Your message
  arrives, the mark goes to `Ouvindo` and breathes, then to `Lendo` — the disc
  stretches into a bar, which is why the disc is authored as a rounded square
  rather than a circle. The proposal is laid down with a clip reveal, because a
  tile is laid rather than faded. Its rows stagger, because they are a list. Then
  the mark lifts to `Esperando você` and stops.
- **It cannot resolve, and that is the point.** `Guardado` — the disc settling
  and taking moss — is licensed by exactly one event: a person confirmed
  something. Nobody on a marketing page has. So the site's one authored sequence
  ends in waiting and holds there. The product's grammar is enforced by its own
  motion vocabulary rather than by a caption.
- **The resting document already draws the waiting pose.** The disc's default
  transform is the `Esperando você` lift, and the sequence arrives at it. A state
  that exists only in movement does not exist in a screenshot.
- **The portrait's bands land once** when the chart is seen, in document order,
  which is household order. The stagger follows the DOM precisely so it can never
  become the ranking the caption disclaims.
- **Everything else is feedback**: a press scale on controls, a disclosure that
  grows via `::details-content`, a dialog that arrives with `@starting-style` and
  leaves faster than it came, and the two script-swapped states — waitlist
  success and the invite verdict — animating on insert.

**Motion is opt-in, and the resting page is the finished frame.** The old
`.reveal` pattern hid content and asked JavaScript to reveal it, which is why it
needed a `<noscript>` stylesheet to stop the page rendering blank. That is
inverted now: everything is in its final state, and a class adds the animation.
No script, an old browser, or `prefers-reduced-motion` all get the complete page,
so `public/styles/noscript.css` was deleted rather than maintained.

Two implementation notes worth keeping. The sequences are armed by a measured
`getBoundingClientRect` check on the existing scroll listener, not by
`IntersectionObserver`: the observer is silently absent in some embedded
webviews, and its ratio can never reach a threshold for an element taller than
the viewport, which the hero phone is on a phone. And the disc's offsets are
percentages resolved against the view box, so the same two numbers — 2.2/64 and
10.2/64 of the box — drive both of the mark's masters, exactly as
`NinaMark.swift` computes them.

## 5. Still open

- **The three-step promise is written for the flag-on product.**
  `NINA_AI_V2_ENABLED = NO` is the shipping default, so on the current build
  every proposal is discarded before it reaches the UI and the hero's phone shows
  something a user would not see. This is not new — the old page made the same
  promise — and `docs/rebrand-azulejo.md` §5b already records that the
  advertising is written for the flag-on product. It becomes a lie only if the
  app ships with the flag off.
- **`web/design-references/landing-implementation-*.png` are now historical.**
  They capture the pre-azulejo site. `landing-conversa-alivio.png` is kept and
  still valid: it is the emotional north star `CLAUDE.md` §2 cites, not a layout
  spec.
- **Legal identity is still `replace_with_…`**, so the privacy page still
  self-declares `data-legal-status="incomplete"` and the online preflight still
  fails. Unchanged by this pass, and unchangeable by engineering.
